"""
Test Phase 4:
- Kết hợp capture + YOLO detector.
- Hiển thị bounding box người lên hình.

Chạy từ root project:
    cd F:\work_space\mon_hoc\HRI\coffee_vision
    .venv\Scripts\activate
    python -m camera2d_pipeline.tests.test_detector_on_camera
"""

import logging
import queue
import threading
import time

import cv2

from .. import capture, config, detector


def draw_detections(frame, detections):
    """
    Vẽ bbox & score lên frame để debug.
    detections là list dict từ detector.detect_persons().
    """
    for det in detections:
        x1, y1, x2, y2 = det["bbox"]
        score = det["score"]

        # Chuyển float sang int pixel
        x1_i, y1_i, x2_i, y2_i = map(int, [x1, y1, x2, y2])

        cv2.rectangle(frame, (x1_i, y1_i), (x2_i, y2_i), (0, 255, 0), 2)
        label = f"Person {score:.2f}"
        cv2.putText(
            frame,
            label,
            (x1_i, max(0, y1_i - 5)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 255, 0),
            1,
            cv2.LINE_AA,
        )


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="[%(asctime)s] [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S",
    )

    logging.info("=== TEST DETECTOR ON CAMERA START ===")
    logging.info("Loading config & model...")
    config.print_config_summary()

    # Khởi động trước model YOLO để lỗi (nếu có) hiện ngay
    detector.load_model()

    frame_queue: "queue.Queue" = queue.Queue(maxsize=1)
    stop_event = threading.Event()

    # Start capture thread
    t_capture = threading.Thread(
        target=capture.capture_loop,
        name="CaptureThread",
        args=(frame_queue, stop_event, config),
        daemon=True,
    )
    t_capture.start()

    last_frame_time = 0.0
    delay = 1.0 / max(config.DEBUG_FPS, 1)

    try:
        while True:
            try:
                frame = frame_queue.get(timeout=1.0)
            except queue.Empty:
                logging.warning("Không nhận được frame nào từ camera (queue rỗng).")
                continue

            # Chạy YOLO detect người
            detections = detector.detect_persons(frame)

            # Vẽ kết quả lên frame
            draw_detections(frame, detections)

            now = time.time()
            if now - last_frame_time < delay:
                continue
            last_frame_time = now

            cv2.imshow("Camera2D - Test Detector (Persons)", frame)

            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q")):  # ESC hoặc 'q'
                logging.info("Người dùng yêu cầu thoát (ESC/q).")
                break

    except KeyboardInterrupt:
        logging.info("Ctrl+C - dừng test detector.")

    finally:
        stop_event.set()
        t_capture.join(timeout=5.0)
        cv2.destroyAllWindows()
        logging.info("=== TEST DETECTOR ON CAMERA STOP ===")


if __name__ == "__main__":
    main()
