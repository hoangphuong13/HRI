"""
events.py

Định nghĩa cấu trúc Event "đàng hoàng" (dataclass),
nhưng vẫn tương thích với cách dùng dict hiện tại.

- logic.py hiện đang push dict vào event_queue.
- comms.py sẽ hỗ trợ cả dict lẫn Event object.

Sau này nếu bạn muốn "nâng cấp" logic.py để dùng Event thay vì dict,
chỉ cần sửa _push_event() trong logic.py để tạo Event và .to_dict() là xong.
"""

from dataclasses import dataclass, asdict, field
from typing import Any, Dict, Optional
import time


@dataclass
class Event:
    """
    Cấu trúc sự kiện chuẩn cho module vision.

    - event: tên sự kiện, ví dụ:
        "ENTER_WORK_AREA"
        "EXIT_WORK_AREA"
        "NEW_CUSTOMER_DETECTED"
        "SAFETY_ALERT"
    - track_id: ID người (theo tracker), có thể None
    - zone: tên vùng hiện tại, có thể None
    - timestamp: thời điểm tạo event (epoch time, giây)
    """
    event: str
    track_id: Optional[int] = None
    zone: Optional[str] = None
    timestamp: float = field(default_factory=time.time)

    def to_dict(self) -> Dict[str, Any]:
        """Chuyển sang dict phục vụ serialize JSON, logging, v.v."""
        return asdict(self)
