"""
logic.py

Nhiệm vụ:
- Nhận frame từ frame_queue.
- Dùng YOLO (detector.detect_persons) để phát hiện người.
- Track người bằng centroid-tracking đơn giản (tạo track_id ổn định).
- Xác định zone (OUTSIDE / WORK_AREA / CUSTOMER_ZONE / DANGER_ZONE).
- Chạy state machine cho từng người:
    + ENTER/EXIT_WORK_AREA
    + NEW_CUSTOMER_DETECTED (đứng trong CUSTOMER_ZONE đủ lâu & đủ yên)
    + SAFETY_ALERT (vào DANGER_ZONE, có cooldown)
- Đẩy event (dict) vào event_queue.

Nếu bật visualization trong config:
- Vẽ polygon các zone.
- Vẽ bbox + track_id + zone lên frame.
- Hiển thị cửa sổ debug, nhấn 'q' hoặc ESC để thoát (set stop_event).

Hàm entry chính:
    process_loop(frame_queue, event_queue, stop_event, cfg)
"""

import logging
import math
import time
from collections import deque
from typing import Any, Deque, Dict, List, Tuple

import cv2
import numpy as np

from . import config, detector


# ---------- Cấu trúc lưu trạng thái mỗi người ---------- #


class PersonState:
    def __init__(self, track_id: int):
        self.track_id: int = track_id
        self.current_zone: str = "OUTSIDE"
        self.last_zone: str = "OUTSIDE"

        self.enter_time_customer: float | None = None
        self.has_notified_customer: bool = False

        # Lưu lịch sử vị trí (cx, cy) để tính tốc độ
        self.positions: Deque[Tuple[float, float]] = deque(maxlen=10)

        # Lưu bbox cuối cùng (x1, y1, x2, y2)
        self.last_bbox: Tuple[float, float, float, float] | None = None

        # Thời điểm cuối cùng thấy người này
        self.last_seen: float = time.time()

        # Thời điểm cuối cùng bắn cảnh báo an toàn
        self.last_alert_time: float = 0.0

    def add_position(self, cx: float, cy: float):
        self.positions.append((cx, cy))
        self.last_seen = time.time()

    def average_speed(self) -> float:
        """
        Tính tốc độ trung bình (pixel/frame) dựa trên positions.
        Nếu < 2 điểm thì coi như đứng yên (0).
        """
        if len(self.positions) < 2:
            return 0.0

        dists = []
        pts = list(self.positions)
        for i in range(1, len(pts)):
            x1, y1 = pts[i - 1]
            x2, y2 = pts[i]
            d = math.hypot(x2 - x1, y2 - y1)
            dists.append(d)

        if not dists:
            return 0.0

        return sum(dists) / len(dists)


# ---------- Helper: geometry & zone ---------- #


def _compute_centroid(bbox: Tuple[float, float, float, float]) -> Tuple[float, float]:
    x1, y1, x2, y2 = bbox
    return (0.5 * (x1 + x2), 0.5 * (y1 + y2))


def point_in_polygon(point: Tuple[float, float], polygon: List[List[float]]) -> bool:
    """
    Kiểm tra 1 điểm có nằm trong polygon hay không (ray casting).
    polygon: list [[x1, y1], [x2, y2], ...]
    """
    if not polygon or len(polygon) < 3:
        return False

    x, y = point
    inside = False

    n = len(polygon)
    for i in range(n):
        x1, y1 = polygon[i]
        x2, y2 = polygon[(i + 1) % n]

        # Kiểm tra giao với đoạn ray ngang
        cond1 = (y1 > y) != (y2 > y)
        if cond1:
            # Tính hoành độ giao điểm
            xinters = (x2 - x1) * (y - y1) / (y2 - y1 + 1e-9) + x1
            if x < xinters:
                inside = not inside

    return inside


def get_zone_for_point(cx: float, cy: float) -> str:
    """
    Trả về tên zone tương ứng với vị trí (cx, cy).
    Ưu tiên: DANGER_ZONE > CUSTOMER_ZONE > WORK_AREA > OUTSIDE
    """
    p = [cx, cy]
    zones = config.ZONES

    danger_poly = zones.get("DANGER_ZONE") or []
    customer_poly = zones.get("CUSTOMER_ZONE") or []
    work_poly = zones.get("WORK_AREA") or []

    if danger_poly and point_in_polygon(p, danger_poly):
        return "DANGER_ZONE"
    if customer_poly and point_in_polygon(p, customer_poly):
        return "CUSTOMER_ZONE"
    if work_poly and point_in_polygon(p, work_poly):
        return "WORK_AREA"
    return "OUTSIDE"


# ---------- Helper: event ---------- #


def _push_event(
    event_queue,
    event_type: str,
    track_id: int | None,
    zone: str | None = None,
):
    """
    Đưa event dạng dict vào event_queue (non-blocking).
    """
    evt = {
        "event": event_type,
        "track_id": track_id,
        "zone": zone,
        "timestamp": time.time(),
    }
    try:
        event_queue.put_nowait(evt)
    except Exception:
        # Nếu queue đầy thì log warning và bỏ event
        logging.warning("Event queue full, drop event: %s", evt)


# ---------- Helper: tracking đơn giản ---------- #


def _associate_detections_to_tracks(
    detections: List[Dict[str, Any]],
    tracks: Dict[int, PersonState],
    max_distance: float = 80.0,
) -> Tuple[Dict[int, int], List[int]]:
    """
    Ghép detection với track bằng centroid-nearest-neighbor.

    Trả về:
        det_to_track: dict[det_idx] = track_id
        unmatched_det_indices: list các chỉ số detection chưa được gán
    """
    det_to_track: Dict[int, int] = {}
    unmatched_dets: List[int] = list(range(len(detections)))

    if not tracks or not detections:
        return det_to_track, unmatched_dets

    # Tính centroid cho tất cả detections
    det_centers = [
        _compute_centroid(det["bbox"]) for det in detections
    ]

    # Với mỗi track, tìm detection gần nhất
    for track_id, state in tracks.items():
        if not state.positions:
            # Nếu chưa có position (track mới tạo mà chưa cập nhật) thì bỏ qua
            continue

        last_cx, last_cy = state.positions[-1]
        best_det_idx = None
        best_dist = None

        for det_idx in unmatched_dets:
            cx, cy = det_centers[det_idx]
            dist = math.hypot(cx - last_cx, cy - last_cy)
            if best_dist is None or dist < best_dist:
                best_dist = dist
                best_det_idx = det_idx

        if best_det_idx is not None and best_dist is not None and best_dist <= max_distance:
            det_to_track[best_det_idx] = track_id
            unmatched_dets.remove(best_det_idx)

    return det_to_track, unmatched_dets


# ---------- Logic cho từng track ---------- #


def _handle_enter_exit_work_area(
    state: PersonState,
    event_queue,
):
    if state.last_zone != "WORK_AREA" and state.current_zone == "WORK_AREA":
        _push_event(event_queue, "ENTER_WORK_AREA", state.track_id, state.current_zone)

    if state.last_zone == "WORK_AREA" and state.current_zone != "WORK_AREA":
        _push_event(event_queue, "EXIT_WORK_AREA", state.track_id, state.current_zone)


def _handle_customer_logic(
    state: PersonState,
    event_queue,
):
    now = time.time()

    if state.current_zone == "CUSTOMER_ZONE":
        if state.enter_time_customer is None:
            state.enter_time_customer = now

        dwell_time = now - state.enter_time_customer
        speed = state.average_speed()

        if (
            not state.has_notified_customer
            and dwell_time >= config.T_CUSTOMER_SECONDS
            and speed <= config.SPEED_THRESHOLD
        ):
            _push_event(event_queue, "NEW_CUSTOMER_DETECTED", state.track_id, state.current_zone)
            state.has_notified_customer = True
    else:
        # Ra khỏi vùng CUSTOMER_ZONE thì reset thời gian chờ
        state.enter_time_customer = None


def _handle_safety_logic(
    state: PersonState,
    event_queue,
):
    now = time.time()

    if state.current_zone == "DANGER_ZONE":
        if now - state.last_alert_time >= config.SAFETY_ALERT_COOLDOWN:
            _push_event(event_queue, "SAFETY_ALERT", state.track_id, state.current_zone)
            state.last_alert_time = now


# ---------- Visualization ---------- #


def _draw_zones(frame: np.ndarray):
    zones = config.ZONES

    colors = {
        "WORK_AREA": (255, 255, 0),      # cyan
        "CUSTOMER_ZONE": (0, 255, 255),  # yellow
        "DANGER_ZONE": (0, 0, 255),      # red
    }

    for name, poly in zones.items():
        if not poly or len(poly) < 3:
            continue
        pts = np.array(poly, dtype=np.int32)
        cv2.polylines(frame, [pts], isClosed=True, color=colors.get(name, (255, 255, 255)), thickness=2)
        # Vẽ tên zone gần điểm đầu
        x, y = pts[0]
        cv2.putText(
            frame,
            name,
            (int(x), int(y) - 5),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            colors.get(name, (255, 255, 255)),
            1,
            cv2.LINE_AA,
        )


def _draw_tracks(frame: np.ndarray, tracks: Dict[int, PersonState]):
    for state in tracks.values():
        if state.last_bbox is None or not state.positions:
            continue

        x1, y1, x2, y2 = state.last_bbox
        x1_i, y1_i, x2_i, y2_i = map(int, [x1, y1, x2, y2])

        # Màu tuỳ theo zone
        color = (0, 255, 0)  # default: green
        if state.current_zone == "DANGER_ZONE":
            color = (0, 0, 255)  # red
        elif state.current_zone == "CUSTOMER_ZONE":
            color = (0, 255, 255)  # yellow
        elif state.current_zone == "WORK_AREA":
            color = (255, 255, 0)  # cyan

        cv2.rectangle(frame, (x1_i, y1_i), (x2_i, y2_i), color, 2)

        label = f"ID:{state.track_id} {state.current_zone}"
        cv2.putText(
            frame,
            label,
            (x1_i, max(0, y1_i - 5)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            color,
            1,
            cv2.LINE_AA,
        )


# ---------- Vòng lặp chính của logic ---------- #


def process_loop(frame_queue, event_queue, stop_event, cfg):
    """
    Vòng lặp xử lý:
    - Lấy frame từ frame_queue.
    - Detect persons.
    - Track + zone logic + sinh event.
    - (Tuỳ chọn) visualize.

    Được gọi từ main.py trong một thread riêng.
    """

    logging.info("Process loop starting (logic + detector).")
    # Load model trước cho chắc (nếu chưa load)
    detector.load_model()

    tracks: Dict[int, PersonState] = {}
    next_track_id = 1

    last_debug_time = 0.0
    debug_delay = 1.0 / max(config.DEBUG_FPS, 1)

    try:
        while not stop_event.is_set():
            try:
                # Lấy frame mới nhất, chờ tối đa 1s
                frame = frame_queue.get(timeout=1.0)
            except Exception:
                # Không có frame thì tiếp tục vòng lặp
                continue

            if frame is None:
                continue

            # Detect người
            detections = detector.detect_persons(frame)

            # Ghép detection với track
            det_to_track, unmatched_dets = _associate_detections_to_tracks(
                detections, tracks, max_distance=80.0
            )

            # Cập nhật track đã match với detection
            now = time.time()
            updated_track_ids = set()

            for det_idx, track_id in det_to_track.items():
                det = detections[det_idx]
                bbox = det["bbox"]
                cx, cy = _compute_centroid(bbox)

                state = tracks[track_id]
                state.last_bbox = bbox
                state.add_position(cx, cy)

                # Cập nhật zone
                state.last_zone = state.current_zone
                state.current_zone = get_zone_for_point(cx, cy)

                # Logic sự kiện
                _handle_enter_exit_work_area(state, event_queue)
                _handle_customer_logic(state, event_queue)
                _handle_safety_logic(state, event_queue)

                updated_track_ids.add(track_id)

            # Tạo track mới cho những detection chưa match
            for det_idx in unmatched_dets:
                det = detections[det_idx]
                bbox = det["bbox"]
                cx, cy = _compute_centroid(bbox)

                track_id = next_track_id
                next_track_id += 1

                state = PersonState(track_id)
                state.last_bbox = bbox
                state.add_position(cx, cy)

                # Thiết lập zone ban đầu
                state.current_zone = get_zone_for_point(cx, cy)
                state.last_zone = "OUTSIDE"

                # Có thể kiểm tra ENTER_WORK_AREA ngay nếu muốn
                _handle_enter_exit_work_area(state, event_queue)
                _handle_customer_logic(state, event_queue)
                _handle_safety_logic(state, event_queue)

                tracks[track_id] = state
                updated_track_ids.add(track_id)

            # Xoá những track đã mất dấu quá lâu
            to_delete = []
            for track_id, state in tracks.items():
                if track_id in updated_track_ids:
                    continue
                # track không được update trong frame này
                if now - state.last_seen > config.MAX_LOST_TIME:
                    # Nếu muốn, có thể gửi event CUSTOMER_LEFT / EXIT_WORK_AREA bổ sung tại đây
                    to_delete.append(track_id)

            for track_id in to_delete:
                logging.debug("Removing lost track_id=%s", track_id)
                tracks.pop(track_id, None)

            # Visualization
            if config.SHOW_DEBUG_WINDOW:
                cur_time = time.time()
                if cur_time - last_debug_time >= debug_delay:
                    debug_frame = frame.copy()
                    if config.DRAW_ZONES:
                        _draw_zones(debug_frame)
                    if config.DRAW_TRACKS:
                        _draw_tracks(debug_frame, tracks)

                    cv2.imshow("Camera2D - Logic Debug", debug_frame)
                    key = cv2.waitKey(1) & 0xFF
                    if key in (27, ord("q")):
                        logging.info("Người dùng nhấn ESC/q trong cửa sổ debug. Dừng process_loop.")
                        stop_event.set()
                        break

                    last_debug_time = cur_time

    except Exception as e:
        logging.exception("Lỗi trong process_loop: %s", e)

    finally:
        if config.SHOW_DEBUG_WINDOW:
            cv2.destroyWindow("Camera2D - Logic Debug")
        logging.info("Process loop stopped.")
