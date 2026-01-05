"""
capture.py

Nhiệm vụ:
- Mở webcam theo cấu hình trong config.
- Đọc frame liên tục và đẩy vào frame_queue.
- Luôn giữ frame MỚI NHẤT trong queue (các frame cũ bị loại bỏ).
- Dừng sạch sẽ khi stop_event được set.

Được gọi bởi:
    main.py -> start_capture_thread() -> capture_loop(...)
"""

import logging
import time
from typing import Any

import cv2


def _init_camera(cfg: Any) -> cv2.VideoCapture:
    """
    Khởi tạo và cấu hình camera theo config.
    Trả về đối tượng VideoCapture (có thể chưa chắc mở thành công).
    """
    cap = cv2.VideoCapture(cfg.CAMERA_INDEX, cv2.CAP_DSHOW)  # CAP_DSHOW cho Windows ổn định hơn

    # Cài đặt độ phân giải và FPS mong muốn
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, cfg.FRAME_WIDTH)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, cfg.FRAME_HEIGHT)
    cap.set(cv2.CAP_PROP_FPS, cfg.CAMERA_FPS)

    return cap


def capture_loop(frame_queue, stop_event, cfg):
    """
    Vòng lặp đọc camera.

    Tham số:
        frame_queue : queue.Queue - dùng để gửi frame sang thread xử lý
        stop_event  : threading.Event - khi set() thì dừng vòng lặp
        cfg         : module config (camera2d_pipeline.config)

    Thiết kế:
    - Nếu queue đã đầy, bỏ frame cũ đi rồi push frame mới (đảm bảo luôn là frame mới nhất).
    - Khi không đọc được frame, log warning và retry sau một lúc.
    """
    logging.info(
        "Capture loop starting. Camera index=%s, resolution=%dx%d, target FPS=%s",
        cfg.CAMERA_INDEX,
        cfg.FRAME_WIDTH,
        cfg.FRAME_HEIGHT,
        cfg.CAMERA_FPS,
    )

    cap = _init_camera(cfg)

    if not cap.isOpened():
        logging.error("Không mở được camera (index=%s). Kiểm tra kết nối USB.", cfg.CAMERA_INDEX)
        return

    # Đo FPS thực tế (tuỳ chọn, dùng cho debug)
    last_time = time.time()
    frames_count = 0

    try:
        while not stop_event.is_set():
            ret, frame = cap.read()

            if not ret or frame is None:
                logging.warning("Đọc frame từ camera thất bại, thử lại sau 0.1s...")
                time.sleep(0.1)
                continue

            # Bỏ frame cũ, giữ frame mới nhất
            if frame_queue.full():
                try:
                    frame_queue.get_nowait()
                except Exception:
                    # Hiếm khi xảy ra, có thể do race condition, bỏ qua
                    pass

            try:
                frame_queue.put_nowait(frame)
            except Exception:
                # Nếu vì lý do gì đó put thất bại thì bỏ qua frame này
                logging.debug("Không put được frame vào queue (bị full?). Bỏ qua frame này.")
                continue

            # Đo FPS thực tế mỗi 2 giây (debug)
            frames_count += 1
            now = time.time()
            if now - last_time >= 2.0:
                fps = frames_count / (now - last_time)
                logging.debug("Capture FPS thực tế: %.1f", fps)
                last_time = now
                frames_count = 0

    except Exception as e:
        logging.exception("Lỗi không mong muốn trong capture_loop: %s", e)

    finally:
        cap.release()
        logging.info("Capture loop stopped. Camera released.")
