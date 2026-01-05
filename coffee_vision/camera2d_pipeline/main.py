"""
Main của module VISION cho máy bán cafe.

Chức năng:
- Khởi tạo logging, queue, stop_event.
- Tạo 3 thread:
    1) capture_loop  : đọc frame từ webcam và đẩy vào frame_queue
    2) process_loop  : lấy frame, chạy detect + tracking + zone logic,
                       đẩy event vào event_queue
    3) comms_loop    : lấy event từ event_queue và gửi lên hệ thống trung tâm
- Quản lý vòng đời: Ctrl+C để dừng, join thread gọn gàng.

Lưu ý:
- File này chỉ là main của module camera, không phải main của toàn hệ thống.
- Các module capture.py, logic.py, comms.py cần cung cấp
  các hàm entrypoint như dưới (xem comment trong từng chỗ gọi).

  Lệnh chạy:  python -m camera2d_pipeline.main

"""

import logging
import logging.handlers
import os
import queue
import threading
import time

# import các module nội bộ
from . import config  # file config.py để load config.yaml
from . import capture  # bạn sẽ viết hàm capture_loop ở đây
from . import logic    # bạn sẽ viết hàm process_loop ở đây (YOLO + tracking + zone)
from . import comms    # bạn sẽ viết hàm comms_loop ở đây (socket / mqtt / ...)
# from . import events # nếu cần class Event riêng thì import thêm


# -------------------- LOGGING SETUP -------------------- #

def setup_logging():
    """
    Thiết lập logging ghi ra cả console và file logs/vision.log
    """
    logs_dir = os.path.join(os.path.dirname(__file__), "logs")
    os.makedirs(logs_dir, exist_ok=True)

    log_file = os.path.join(logs_dir, "vision.log")

    logger = logging.getLogger()  # root logger
    logger.setLevel(logging.INFO)

    # Format chung
    formatter = logging.Formatter(
        "[%(asctime)s] [%(levelname)s] [%(threadName)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Handler ghi file (xoay vòng cho đỡ nặng)
    file_handler = logging.handlers.RotatingFileHandler(
        log_file, maxBytes=5 * 1024 * 1024, backupCount=3, encoding="utf-8"
    )
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)

    # Handler in ra console
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)

    logging.info("Logging initialized. Log file: %s", log_file)


# -------------------- THREAD WRAPPERS -------------------- #

def start_capture_thread(frame_queue, stop_event):
    """
    Tạo và start thread đọc camera.

    Yêu cầu trong capture.py phải có hàm:

        def capture_loop(frame_queue, stop_event, cfg):
            # đọc từ webcam, push frame vào frame_queue

    """
    t = threading.Thread(
        target=capture.capture_loop,
        name="CaptureThread",
        args=(frame_queue, stop_event, config),
        daemon=True,  # cho phép chương trình thoát nếu các thread khác xong
    )
    t.start()
    logging.info("Capture thread started.")
    return t


def start_processing_thread(frame_queue, event_queue, stop_event):
    """
    Tạo và start thread xử lý (YOLO + logic).

    Yêu cầu trong logic.py phải có hàm:

        def process_loop(frame_queue, event_queue, stop_event, cfg):
            # lấy frame, detect/tracking, zone logic, push event vào event_queue

    (Bên trong logic.process_loop bạn có thể gọi detector.py)
    """
    t = threading.Thread(
        target=logic.process_loop,
        name="ProcessThread",
        args=(frame_queue, event_queue, stop_event, config),
        daemon=True,
    )
    t.start()
    logging.info("Processing thread started.")
    return t


def start_comms_thread(event_queue, stop_event):
    """
    Tạo và start thread gửi event lên hệ thống trung tâm.

    Yêu cầu trong comms.py phải có hàm:

        def comms_loop(event_queue, stop_event, cfg):
            # lấy event từ queue, gửi qua socket / mqtt / http...

    """
    t = threading.Thread(
        target=comms.comms_loop,
        name="CommsThread",
        args=(event_queue, stop_event, config),
        daemon=True,
    )
    t.start()
    logging.info("Comms thread started.")
    return t


# -------------------- MAIN ENTRYPOINT -------------------- #

def main():
    setup_logging()
    logging.info("=== VISION MODULE STARTING ===")

    # Queue chia sẻ giữa các thread
    frame_queue: "queue.Queue" = queue.Queue(maxsize=1)   # chỉ giữ frame mới nhất
    event_queue: "queue.Queue" = queue.Queue(maxsize=100)

    # Event để báo dừng cho các thread
    stop_event = threading.Event()

        # Start các thread
    capture_thread = start_capture_thread(frame_queue, stop_event)
    process_thread = start_processing_thread(frame_queue, event_queue, stop_event)
    comms_thread = start_comms_thread(event_queue, stop_event)

    last_heartbeat = time.time()
    try:
        # Vòng lặp chính chỉ để giữ chương trình sống,
        # và thỉnh thoảng in heartbeat để biết main vẫn chạy.
        while True:
            time.sleep(1)
            if time.time() - last_heartbeat > 30:
                logging.debug("Vision main heartbeat...")
                last_heartbeat = time.time()
    except KeyboardInterrupt:
        logging.info("Ctrl+C detected. Stopping vision module...")
    finally:
        # Ra hiệu cho tất cả thread dừng
        stop_event.set()
        # Chờ thread kết thúc gọn gàng
        capture_thread.join(timeout=5.0)
        process_thread.join(timeout=5.0)
        comms_thread.join(timeout=5.0)

        logging.info("=== VISION MODULE STOPPED ===")



if __name__ == "__main__":
    # Gợi ý cách chạy:
    #   cd F:\work_space\mon_hoc\HRI\coffee_vision
    #   python -m camera2d_pipeline.main
    main()
