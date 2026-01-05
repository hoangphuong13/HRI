"""
Test Phase 5:
- Chạy capture + logic (YOLO + zone + event).
- Hiển thị cửa sổ debug (vùng & track) nếu bật trong config.
- In các event ra console.

Chạy từ root project:
    cd F:\work_space\mon_hoc\HRI\coffee_vision
    .venv\Scripts\activate
    python -m camera2d_pipeline.tests.test_logic_debug
"""

import logging
import queue
import threading
import time

from .. import capture, config, logic


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="[%(asctime)s] [%(levelname)s] [%(threadName)s] %(message)s",
        datefmt="%H:%M:%S",
    )

    logging.info("=== TEST LOGIC DEBUG START ===")
    config.print_config_summary()

    frame_queue: "queue.Queue" = queue.Queue(maxsize=1)
    event_queue: "queue.Queue" = queue.Queue(maxsize=100)
    stop_event = threading.Event()

    # Start capture thread
    t_capture = threading.Thread(
        target=capture.capture_loop,
        name="CaptureThread",
        args=(frame_queue, stop_event, config),
        daemon=True,
    )
    t_capture.start()

    # Start logic thread
    t_logic = threading.Thread(
        target=logic.process_loop,
        name="LogicThread",
        args=(frame_queue, event_queue, stop_event, config),
        daemon=True,
    )
    t_logic.start()

    try:
        while not stop_event.is_set():
            try:
                evt = event_queue.get(timeout=0.5)
            except queue.Empty:
                continue

            # In event ra console
            logging.info("EVENT: %s", evt)

    except KeyboardInterrupt:
        logging.info("Ctrl+C - dừng test logic.")

    finally:
        stop_event.set()
        t_capture.join(timeout=5.0)
        t_logic.join(timeout=5.0)
        logging.info("=== TEST LOGIC DEBUG STOP ===")


if __name__ == "__main__":
    main()
