"""
Test đơn giản cho Phase 3:
- Chạy riêng capture_loop trong một thread.
- Lấy frame từ frame_queue và hiển thị bằng cv2.imshow.
- Nhấn phím 'q' hoặc ESC để thoát.

Cái này chỉ để kiểm tra:
- Camera mở được chưa
- Góc quay đã đúng chưa

Lệnh chạy: python -m camera2d_pipeline.tests.test_capture_only
"""

import logging
import queue
import threading
import time

import cv2

from .. import capture, config


def main():
    # Logging đơn giản cho test
    logging.basicConfig(
        level=logging.INFO,
        format="[%(asctime)s] [%(levelname)s] %(message)s",
        datefmt="%H:%M:%S",
    )

    logging.info("=== TEST CAPTURE ONLY START ===")

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
                # Chờ frame mới tối đa 1 giây
                frame = frame_queue.get(timeout=1.0)
            except queue.Empty:
                logging.warning("Không nhận được frame nào từ camera (queue rỗng).")
                continue

            now = time.time()
            # Giới hạn FPS hiển thị để đỡ nặng (dùng config.DEBUG_FPS)
            if now - last_frame_time < delay:
                continue
            last_frame_time = now

            cv2.imshow("Camera2D - Test Capture Only", frame)

            key = cv2.waitKey(1) & 0xFF
            if key in (27, ord("q")):  # ESC hoặc 'q'
                logging.info("Người dùng yêu cầu thoát (ESC/q).")
                break

    except KeyboardInterrupt:
        logging.info("Ctrl+C - dừng test capture.")

    finally:
        stop_event.set()
        t_capture.join(timeout=5.0)
        cv2.destroyAllWindows()
        logging.info("=== TEST CAPTURE ONLY STOP ===")


if __name__ == "__main__":
    main()
