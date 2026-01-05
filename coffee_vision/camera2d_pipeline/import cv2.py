import cv2
import numpy as np
from ultralytics import YOLO
from collections import deque
import requests
import threading
import time

class Config:
    MODEL_PATH = "yolov8n.pt"
    CONF_THRES = 0.5
    PERSON_CLASS_ID = 0
    CAMERA_SOURCE = 1  
    SERVER_URL = "http://192.168.1.136:5000"
    
    WARNING_DISTANCE_M = 1.5   # Ngưỡng khách đến
    LEAVING_THRESHOLD_M = 2.2  # Ngưỡng khách đi
    CONFIRMATION_FRAMES = 5    

def send_signal(endpoint):
    def _req():
        try:
            url = f"{Config.SERVER_URL}/{endpoint}"
            requests.post(url, json={}, timeout=1)
            print(f" [NET] >> Đã gửi tín hiệu tới Server: /{endpoint}")
        except Exception as e:
            print(f" [NET] !! Lỗi gửi tín hiệu: {e}")
    threading.Thread(target=_req).start()

class VisionPipeline:
    def __init__(self):
        print(" [INIT] Đang tải model YOLO...")
        self.model = YOLO(Config.MODEL_PATH)
        self.cap = cv2.VideoCapture(Config.CAMERA_SOURCE, cv2.CAP_DSHOW)
        if not self.cap.isOpened(): self.cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)

        self.k_width = 0.0
        self.is_calibrated = False 
        self.dist_history = deque(maxlen=10)
        
        self.current_mode = "DETECT_ARRIVAL" 
        self.last_check_time = 0
        self.consecutive_frame_count = 0
        
        try: requests.post(f"{Config.SERVER_URL}/reset-system", timeout=1)
        except: pass

    def calibrate(self, current_pixel_width):
        if current_pixel_width > 0:
            self.k_width = 2.0 * current_pixel_width
            self.is_calibrated = True 
            print(f" [CALIB] Đã hiệu chỉnh xong! K_WIDTH = {self.k_width:.2f}")

    def run(self):
        print("--- VISION READY ---")
        
        while True:
            # 1. Polling Server để cập nhật trạng thái
            # Đây là bước quan trọng: Server sẽ bảo Vision biết khi nào "Dịch vụ xong"
            if time.time() - self.last_check_time > 1.0:
                try:
                    resp = requests.get(f"{Config.SERVER_URL}/camera-mode", timeout=0.5)
                    if resp.status_code == 200:
                        server_mode = resp.json().get("mode", "IDLE")
                        # Cập nhật mode từ Server (ví dụ: Server chuyển từ SERVING -> DETECT_DEPARTURE)
                        if server_mode != self.current_mode and server_mode != "IDLE":
                            print(f" [SYNC] Server yêu cầu chuyển chế độ: {server_mode}")
                            self.current_mode = server_mode
                            self.consecutive_frame_count = 0
                except: pass
                self.last_check_time = time.time()

            ret, frame = self.cap.read()
            if not ret: break
            screen_h, screen_w = frame.shape[:2]

            # [cite_start]2. Nhận diện người [cite: 1]
            results = self.model(frame, verbose=False, stream=True)
            max_w = 0 
            best_box = None
            
            for r in results:
                for box in r.boxes:
                    if int(box.cls[0]) == Config.PERSON_CLASS_ID and float(box.conf[0]) >= Config.CONF_THRES:
                        x1, y1, x2, y2 = map(int, box.xyxy[0])
                        w = x2 - x1 
                        if w > max_w: 
                            max_w = w
                            best_box = (x1, y1, x2, y2)

            # 3. Tính khoảng cách
            avg_dist = 0.0
            valid_measurement = False
            if max_w > 0 and self.is_calibrated:
                touching_side = (best_box[0] < 5) or (best_box[2] > screen_w - 5)
                if not touching_side:
                    dist = self.k_width / max_w
                    self.dist_history.append(dist)
                    avg_dist = sum(self.dist_history) / len(self.dist_history)
                    valid_measurement = True
                    
                    color = (0, 165, 255) if avg_dist < Config.WARNING_DISTANCE_M else (0, 255, 0)
                    cv2.rectangle(frame, (best_box[0], best_box[1]), (best_box[2], best_box[3]), color, 2)
                    cv2.putText(frame, f"{avg_dist:.2f}m", (best_box[0], best_box[1]-10), cv2.FONT_HERSHEY_SIMPLEX, 0.8, color, 2)

            # [cite_start]4. LOGIC CHÍNH (Đã sửa đổi) [cite: 1]
            if valid_measurement:
                # --- TRƯỜNG HỢP 1: ĐANG CHỜ KHÁCH ĐẾN ---
                if self.current_mode == "DETECT_ARRIVAL":
                    if avg_dist < Config.WARNING_DISTANCE_M: 
                        self.consecutive_frame_count += 1
                        if self.consecutive_frame_count >= Config.CONFIRMATION_FRAMES:
                            print(f" [EVENT] KHÁCH ĐẾN ({avg_dist:.2f}m) -> Gửi notify-arrival")
                            send_signal("notify-arrival")
                            # Chuyển sang SERVING và "ngủ đông" logic, chờ Server báo xong việc
                            self.current_mode = "SERVING" 
                            self.consecutive_frame_count = 0
                    else:
                        self.consecutive_frame_count = 0
                
                # --- TRƯỜNG HỢP 2: ĐANG CHỜ KHÁCH ĐI (Chỉ chạy khi Server đã bật mode này) ---
                # Đã xóa "SERVING" khỏi danh sách check
                elif self.current_mode == "DETECT_DEPARTURE":
                    if avg_dist > Config.LEAVING_THRESHOLD_M: 
                        self.consecutive_frame_count += 1
                        if self.consecutive_frame_count >= Config.CONFIRMATION_FRAMES:
                            print(f" [EVENT] KHÁCH ĐI ({avg_dist:.2f}m) -> Gửi notify-departure")
                            send_signal("notify-departure")
                            self.current_mode = "DETECT_ARRIVAL" 
                            self.consecutive_frame_count = 0
                    else:
                        self.consecutive_frame_count = 0
                
                # --- TRƯỜNG HỢP 3: ĐANG PHỤC VỤ (SERVING) ---
                # Không làm gì cả, chỉ hiện khoảng cách lên màn hình
                elif self.current_mode == "SERVING":
                    self.consecutive_frame_count = 0
            
            else:
                self.consecutive_frame_count = 0

            # Hiển thị
            status_text = f"MODE: {self.current_mode}"
            cv2.putText(frame, status_text, (20, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2)
            if not self.is_calibrated:
                cv2.putText(frame, "BAM 'C' DE CALIB (DUNG CACH 2M)", (20, screen_h - 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)

            cv2.imshow("Robot Barista Vision", frame)
            
            key = cv2.waitKey(1)
            if key == ord('q'): break
            elif key == ord('c') or key == ord('C'): 
                if max_w > 0: self.calibrate(max_w)

        self.cap.release()
        cv2.destroyAllWindows()

if __name__ == "__main__":
    VisionPipeline().run()