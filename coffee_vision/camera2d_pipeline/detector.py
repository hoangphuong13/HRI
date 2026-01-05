"""
detector.py

Nhiệm vụ:
- Load model YOLO một lần (singleton).
- Cung cấp hàm detect_persons(frame) để:
    + Nhận 1 frame BGR (numpy array, từ OpenCV)
    + Trả về danh sách bbox người: list dict:
        {
            "bbox": (x1, y1, x2, y2),
            "score": float,
            "class_id": int,  # luôn là 0 (person) trong COCO
        }

Lưu ý:
- Chỉ lọc class = 'person' (id = 0 trong COCO).
- Các tham số (weights_path, conf, iou, device) lấy từ config.py
"""

import logging
from typing import Any, Dict, List, Tuple

import numpy as np
from ultralytics import YOLO

from . import config

# Model YOLO (singleton)
_model: YOLO | None = None


def load_model() -> YOLO:
    """
    Load model YOLO (nếu chưa load) và trả về instance.

    Dùng config.MODEL_WEIGHTS_PATH & config.MODEL_DEVICE.
    """
    global _model
    if _model is not None:
        return _model

    logging.info(
        "Loading YOLO model from '%s' (device=%s)...",
        config.MODEL_WEIGHTS_PATH,
        config.MODEL_DEVICE,
    )

    try:
        model = YOLO(config.MODEL_WEIGHTS_PATH)
        # Chuyển model sang device (cpu/cuda)
        # Lưu ý: nếu device không hợp lệ thì ultralytics sẽ tự báo lỗi.
        model.to(config.MODEL_DEVICE)
    except Exception as e:
        logging.exception("Không load được YOLO model: %s", e)
        raise

    _model = model
    logging.info("YOLO model loaded successfully.")
    return _model


def detect_persons(
    frame: np.ndarray,
) -> List[Dict[str, Any]]:
    """
    Chạy YOLO trên 1 frame và trả về danh sách detection của class 'person'.

    Tham số:
        frame: ảnh BGR từ OpenCV (shape: H x W x 3, dtype=uint8)

    Trả về:
        List[dict] với mỗi dict:
            {
                "bbox": (x1, y1, x2, y2),
                "score": float,
                "class_id": int
            }
    """
    model = load_model()

    if frame is None or not isinstance(frame, np.ndarray):
        logging.warning("detect_persons: frame không hợp lệ (None hoặc không phải ndarray).")
        return []

    # YOLO của ultralytics chấp nhận BGR numpy trực tiếp
    try:
        results = model(
            frame,
            conf=config.MODEL_CONF_THRESHOLD,
            iou=config.MODEL_IOU_THRESHOLD,
            device=config.MODEL_DEVICE,
            verbose=False,
        )
    except Exception as e:
        logging.exception("Lỗi khi chạy YOLO detect: %s", e)
        return []

    detections: List[Dict[str, Any]] = []

    # results có thể là 1 list các Results (thường chỉ 1 phần tử vì input là 1 frame)
    for r in results:
        boxes = r.boxes  # Boxes object
        if boxes is None:
            continue

        for box in boxes:
            # class id
            cls_id = int(box.cls[0]) if box.cls is not None else -1

            # Chỉ lấy 'person' (thường là 0 trong COCO)
            if cls_id != 0:
                continue

            # bbox toạ độ [x1, y1, x2, y2]
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            score = float(box.conf[0]) if box.conf is not None else 0.0

            detections.append(
                {
                    "bbox": (x1, y1, x2, y2),
                    "score": score,
                    "class_id": cls_id,
                }
            )

    return detections
