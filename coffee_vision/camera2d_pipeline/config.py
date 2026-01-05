"""
config.py

Nhiệm vụ:
- Load file config.yaml một lần.
- Cung cấp các hằng số & helper để các module khác (capture, logic, detector, comms)
  import dùng cho gọn.

Cách dùng ví dụ:
    from . import config

    idx = config.CAMERA_INDEX
    zones = config.ZONES
"""

import os
from typing import Any, Dict, List

import yaml


# -------------------- LOAD RAW YAML -------------------- #

# Đường dẫn tuyệt đối tới file config.yaml (nằm cùng thư mục với file này)
CONFIG_PATH = os.path.join(os.path.dirname(__file__), "config.yaml")


def _load_raw_config() -> Dict[str, Any]:
    if not os.path.exists(CONFIG_PATH):
        raise FileNotFoundError(f"Không tìm thấy file config.yaml tại: {CONFIG_PATH}")

    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    if not isinstance(data, dict):
        raise ValueError("Nội dung config.yaml không hợp lệ (không phải dạng mapping).")

    return data


_CFG = _load_raw_config()   # load một lần khi import module


# -------------------- HELPER LẤY GIÁ TRỊ CÓ DEFAULT -------------------- #

def _get(path: str, default: Any = None) -> Any:
    """
    Lấy giá trị trong dict _CFG bằng đường dẫn dạng "section.key"
    Ví dụ: _get("camera.width", 640)
    """
    keys = path.split(".")
    cur = _CFG
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur


# -------------------- CAMERA -------------------- #

CAMERA_INDEX: int = int(_get("camera.index", 0))
FRAME_WIDTH: int = int(_get("camera.width", 640))
FRAME_HEIGHT: int = int(_get("camera.height", 480))
CAMERA_FPS: int = int(_get("camera.fps", 30))


# -------------------- MODEL (YOLO) -------------------- #

# Đường dẫn tuyệt đối tới file weight YOLO
_MODEL_WEIGHTS_REL = _get("model.weights_path", "yolo11n.pt")
MODEL_WEIGHTS_PATH: str = os.path.join(os.path.dirname(__file__), _MODEL_WEIGHTS_REL)

MODEL_CONF_THRESHOLD: float = float(_get("model.conf_threshold", 0.5))
MODEL_IOU_THRESHOLD: float = float(_get("model.iou_threshold", 0.45))
MODEL_DEVICE: str = str(_get("model.device", "cpu"))


# -------------------- LOGIC -------------------- #

T_CUSTOMER_SECONDS: float = float(_get("logic.customer_dwell_time", 3.0))
SPEED_THRESHOLD: float = float(_get("logic.speed_threshold", 5.0))
MAX_LOST_TIME: float = float(_get("logic.max_lost_time", 1.0))
SAFETY_ALERT_COOLDOWN: float = float(_get("logic.safety_alert_cooldown", 2.0))


# -------------------- ZONES -------------------- #

# Dạng: {"WORK_AREA": [[x1, y1], [x2, y2], ...], ...}
ZONES: Dict[str, List[List[float]]] = _get("zones", {}) or {}


def get_zone_polygon(name: str) -> List[List[float]]:
    """
    Lấy polygon của zone theo tên.
    Nếu không tồn tại, trả về list rỗng.
    """
    zone = ZONES.get(name)
    if not isinstance(zone, list):
        return []
    return zone


# -------------------- COMMS -------------------- #

COMMS_ENABLED: bool = bool(_get("comms.enabled", True))
COMMS_HOST: str = str(_get("comms.host", "127.0.0.1"))
COMMS_PORT: int = int(_get("comms.port", 9000))
COMMS_RECONNECT_SECONDS: float = float(_get("comms.reconnect_seconds", 5.0))


# -------------------- VISUALIZATION / DEBUG -------------------- #

SHOW_DEBUG_WINDOW: bool = bool(_get("visualization.show_debug_window", True))
DRAW_ZONES: bool = bool(_get("visualization.draw_zones", True))
DRAW_TRACKS: bool = bool(_get("visualization.draw_tracks", True))
DEBUG_FPS: int = int(_get("visualization.debug_fps", 10))


# -------------------- DEBUG: IN RA CẤU HÌNH NẾU CẦN -------------------- #

def print_config_summary() -> None:
    """Hàm tiện lợi để in nhanh config lên log/console khi debug."""
    from pprint import pformat  # import trong hàm cho nhẹ

    print("=== CAMERA CONFIG ===")
    print(f"  INDEX = {CAMERA_INDEX}")
    print(f"  RES   = {FRAME_WIDTH}x{FRAME_HEIGHT} @ {CAMERA_FPS} FPS")

    print("\n=== MODEL CONFIG ===")
    print(f"  WEIGHTS = {MODEL_WEIGHTS_PATH}")
    print(f"  CONF    = {MODEL_CONF_THRESHOLD}")
    print(f"  IOU     = {MODEL_IOU_THRESHOLD}")
    print(f"  DEVICE  = {MODEL_DEVICE}")

    print("\n=== LOGIC CONFIG ===")
    print(f"  CUSTOMER_DWELL_TIME = {T_CUSTOMER_SECONDS}")
    print(f"  SPEED_THRESHOLD     = {SPEED_THRESHOLD}")
    print(f"  MAX_LOST_TIME       = {MAX_LOST_TIME}")
    print(f"  SAFETY_COOLDOWN     = {SAFETY_ALERT_COOLDOWN}")

    print("\n=== ZONES ===")
    print(pformat(ZONES))

    print("\n=== COMMS ===")
    print(f"  ENABLED   = {COMMS_ENABLED}")
    print(f"  HOST:PORT = {COMMS_HOST}:{COMMS_PORT}")

    print("\n=== VISUALIZATION ===")
    print(f"  SHOW_WINDOW = {SHOW_DEBUG_WINDOW}")
    print(f"  DRAW_ZONES  = {DRAW_ZONES}")
    print(f"  DRAW_TRACKS = {DRAW_TRACKS}")
    print(f"  DEBUG_FPS   = {DEBUG_FPS}")
