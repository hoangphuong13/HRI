"""
comms.py

Nhiệm vụ:
- Lấy event từ event_queue.
- Nếu config.COMMS_ENABLED = False:
    + Chỉ in event ra log (debug mode).
- Nếu config.COMMS_ENABLED = True:
    + Kết nối TCP tới COMMS_HOST:COMMS_PORT.
    + Serialize event -> JSON + '\n' và gửi đi.
    + Tự động reconnect nếu rớt kết nối.

Lưu ý:
- Event có thể là dict (từ logic.py hiện tại) hoặc Event object (events.Event).
- Được gọi bởi main.py trong một thread riêng: comms_loop(event_queue, stop_event, cfg)
"""

import json
import logging
import socket
import time
from typing import Any, Dict

from . import config
from .events import Event


def _event_to_dict(evt: Any) -> Dict[str, Any]:
    """
    Chuẩn hoá event về dict:
    - Nếu đã là dict -> trả thẳng.
    - Nếu là Event object -> dùng to_dict().
    - Ngược lại -> đóng gói vào dict generic.
    """
    if isinstance(evt, dict):
        return evt
    if isinstance(evt, Event):
        return evt.to_dict()
    # fallback
    return {
        "event": str(getattr(evt, "event", "UNKNOWN")),
        "raw": repr(evt),
        "timestamp": time.time(),
    }


# -------------------- DEBUG MODE (không gửi ra network) -------------------- #


def _debug_loop(event_queue, stop_event):
    """
    Mode đơn giản: chỉ in event ra log.
    Dùng khi config.COMMS_ENABLED = False.
    """
    logging.info("Comms running in DEBUG mode (COMMS_ENABLED = False).")

    while not stop_event.is_set():
        try:
            evt = event_queue.get(timeout=0.5)
        except Exception:
            continue

        evt_dict = _event_to_dict(evt)
        logging.info("[COMMS DEBUG] EVENT OUT -> %s", evt_dict)


# -------------------- TCP CLIENT MODE -------------------- #


def _connect_once(host: str, port: int) -> socket.socket | None:
    """
    Thử connect 1 lần tới (host, port).
    Thành công -> trả về socket; thất bại -> None.
    """
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(5.0)  # timeout cho connect
        sock.connect((host, port))
        sock.settimeout(None)  # giao tiếp sau đó dùng blocking bình thường
        logging.info("COMMS: Connected to %s:%s", host, port)
        return sock
    except Exception as e:
        logging.warning("COMMS: Cannot connect to %s:%s -> %s", host, port, e)
        return None


def _send_event_over_socket(sock: socket.socket, evt_dict: Dict[str, Any]) -> bool:
    """
    Gửi một event (dict) qua socket ở dạng JSON lines.
    Trả về True nếu gửi OK, False nếu gặp lỗi.
    """
    try:
        msg = json.dumps(evt_dict, ensure_ascii=False) + "\n"
        sock.sendall(msg.encode("utf-8"))
        return True
    except Exception as e:
        logging.warning("COMMS: Error while sending event: %s", e)
        return False


def _tcp_loop(event_queue, stop_event):
    """
    Loop chính khi COMMS_ENABLED = True.
    - Tự reconnect nếu mất kết nối.
    - Gửi JSON line cho mỗi event.
    """
    host = config.COMMS_HOST
    port = config.COMMS_PORT
    reconnect_delay = config.COMMS_RECONNECT_SECONDS

    logging.info(
        "Comms running in TCP mode -> %s:%s (reconnect_delay=%.1fs)",
        host,
        port,
        reconnect_delay,
    )

    sock: socket.socket | None = None

    try:
        while not stop_event.is_set():
            # Đảm bảo đã có socket kết nối
            if sock is None:
                sock = _connect_once(host, port)
                if sock is None:
                    # Không connect được -> chờ rồi thử lại
                    logging.info("COMMS: Retry connect after %.1fs...", reconnect_delay)
                    time.sleep(reconnect_delay)
                    continue

            # Lấy event từ queue
            try:
                evt = event_queue.get(timeout=0.5)
            except Exception:
                # Không có event mới -> check stop_event rồi tiếp tục
                continue

            evt_dict = _event_to_dict(evt)
            sent_ok = _send_event_over_socket(sock, evt_dict)
            if not sent_ok:
                # Lỗi khi gửi -> đóng socket, set None để reconnect
                try:
                    sock.close()
                except Exception:
                    pass
                sock = None
                logging.info("COMMS: Connection lost. Will try to reconnect.")
                # Event này đã bị mất, chấp nhận drop (hoặc có thể push lại vào queue nếu muốn)
                continue

    finally:
        if sock is not None:
            try:
                sock.close()
            except Exception:
                pass
        logging.info("COMMS: TCP loop stopped.")


# -------------------- ENTRYPOINT CHO MAIN -------------------- #


def comms_loop(event_queue, stop_event, cfg):
    """
    Hàm được gọi từ main.py trong thread riêng.

    Nếu cfg.COMMS_ENABLED = False:
        -> chạy _debug_loop (in log).

    Nếu True:
        -> chạy _tcp_loop (kết nối real tới hệ thống trung tâm).
    """
    if not cfg.COMMS_ENABLED:
        _debug_loop(event_queue, stop_event)
    else:
        _tcp_loop(event_queue, stop_event)
