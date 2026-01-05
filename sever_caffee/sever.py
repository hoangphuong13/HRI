import os
import requests
from flask import Flask, request, jsonify
from dotenv import load_dotenv
import json
from flask_cors import CORS
from pathlib import Path
import time
import threading

app = Flask(__name__)
CORS(app) # Cho phép Flutter kết nối

# ==============================================================================
# 1. CẤU HÌNH HỆ THỐNG
# ==============================================================================

# --- Load biến môi trường (.env) ---
try:
    script_dir = Path(__file__).resolve().parent
    dotenv_path = script_dir / '.env'
    load_dotenv(dotenv_path=dotenv_path)
    print(f" Đã tải cấu hình từ: {dotenv_path}")
except Exception as e:
    print(f" Không tải được .env: {e}")

# --- Cấu hình AI ---
api_key = os.getenv("OPENROUTER_API_KEY")
OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"

# --- Cấu hình Robot (ESP8266) ---
#  QUAN TRỌNG: Thay IP này bằng IP hiển thị trên Serial Monitor của ESP8266
ESP_ROBOT_URL = "http://192.168.1.100/run-command"

# --- Mapping: ID Món (App) -> ID Kịch bản (Arduino) ---
SCRIPT_MAPPING = {
    "c1": 1, # Cà phê sữa nóng
    "c2": 2, # Matcha latte
    "c3": 3, # Trà đào
    "c4": 4  # Trà dâu
}

# ==============================================================================
# 2. QUẢN LÝ TRẠNG THÁI (STATE MACHINE)
# ==============================================================================
current_state = "WAITING" # WAITING | SERVING | LEAVING
last_activity_time = time.time()
RESET_TIMEOUT = 60 # Tự động reset sau 60s không hoạt động

app_events = {
    "arrival_msg": None,
    "departure_msg": None
}

def update_activity():
    global last_activity_time
    last_activity_time = time.time()

# --- Luồng chạy ngầm: Tự động Reset nếu bị kẹt ---
def auto_reset_loop():
    global current_state, last_activity_time
    while True:
        time.sleep(5)
        if current_state != "WAITING":
            elapsed = time.time() - last_activity_time
            if elapsed > RESET_TIMEOUT:
                print(f" [AUTO-RESET] Hệ thống treo quá {RESET_TIMEOUT}s -> Reset về WAITING")
                reset_system_logic()

threading.Thread(target=auto_reset_loop, daemon=True).start()

def reset_system_logic():
    global current_state
    current_state = "WAITING"
    app_events["arrival_msg"] = None
    app_events["departure_msg"] = None
    update_activity()

# ==============================================================================
# 3. API CHO CAMERA (Vision Pipeline)
# ==============================================================================

@app.route("/reset-system", methods=["POST"])
def reset_system():
    """Camera gọi hàm này khi khởi động để làm sạch trạng thái"""
    print(" [CMD] Camera yêu cầu Reset hệ thống.")
    reset_system_logic()
    return jsonify({"status": "reset_ok"})

@app.route("/camera-mode", methods=["GET"])
def get_camera_mode():
    """Camera hỏi server xem cần phát hiện gì"""
    if current_state != "WAITING": update_activity()
    
    if current_state == "WAITING":
        return jsonify({"mode": "DETECT_ARRIVAL"})
    elif current_state == "LEAVING":
        return jsonify({"mode": "DETECT_DEPARTURE"})
    else:
        return jsonify({"mode": "IDLE"})

@app.route("/notify-arrival", methods=["POST"])
def notify_arrival():
    """Camera báo khách đến"""
    global current_state
    if current_state == "WAITING":
        print(" [SERVER] Khách ĐẾN -> Chuyển sang SERVING")
        current_state = "SERVING" 
        update_activity()
        app_events["arrival_msg"] = "Xin chào quý khách! Mời quý khách xem menu."
        return jsonify({"status": "ok"})
    return jsonify({"status": "ignored"})

@app.route("/notify-departure", methods=["POST"])
def notify_departure():
    """Camera báo khách đi"""
    global current_state
    if current_state == "LEAVING":
        print(" [SERVER] Khách ĐI -> Reset về WAITING")
        current_state = "WAITING" 
        update_activity()
        app_events["departure_msg"] = "Cảm ơn quý khách. Hẹn gặp lại!"
        return jsonify({"status": "ok"})
    return jsonify({"status": "ignored"})

# ==============================================================================
# 4. API CHO FLUTTER APP (Polling & Chat)
# ==============================================================================

@app.route("/check-arrival", methods=["GET"])
def check_arrival():
    """App hỏi server: Có khách đến chưa?"""
    if app_events["arrival_msg"]:
        msg = app_events["arrival_msg"]
        app_events["arrival_msg"] = None 
        return jsonify({"arrived": True, "message": msg})
    return jsonify({"arrived": False})

@app.route("/check-departure", methods=["GET"])
def check_departure():
    """App hỏi server: Khách đã đi chưa?"""
    if app_events["departure_msg"]:
        msg = app_events["departure_msg"]
        app_events["departure_msg"] = None 
        return jsonify({"left": True, "message": msg})
    return jsonify({"left": False})

@app.route("/session-complete", methods=["POST"])
def session_complete():
    """App báo: Đã phục vụ xong (hoặc đóng bot)"""
    global current_state
    if current_state == "SERVING":
        print(" [SERVER] App báo xong -> Chuyển sang LEAVING (Chờ khách đi)")
        current_state = "LEAVING"
        update_activity()
        return jsonify({"status": "ok"})
    
    # Force fix nếu lệch trạng thái
    if current_state == "WAITING":
         print("Đồng bộ trạng thái: WAITING -> LEAVING")
         current_state = "LEAVING"
         update_activity()
         return jsonify({"status": "forced_leaving"})
         
    return jsonify({"status": "ignored"})

# --- LOGIC CHAT BOT ---
def build_system_prompt():
    menu = """
    [
        {"id": "c1", "name": "cà phê sữa nóng", "price": 30000},
        {"id": "c2", "name": "matcha latte nóng", "price": 25000},
        {"id": "c3", "name": "trà đào nóng", "price": 25000},
        {"id": "c4", "name": "trà dâu nóng", "price": 20000}
    ]
    """
    return f"""
    Bạn là nhân viên cà phê tên Phương. Menu: {menu}
    Quy tắc:
    1. Trả lời ngắn gọn, thân thiện.
    2. Khi khách chốt đơn (ví dụ: "lấy cho tôi...", "tôi chọn..."), trả về JSON:
       {{"actions": [{{"item_id": "c1", "quantity": 1}}], "response_speech": "Dạ, 1 cà phê sữa. Tổng 30k ạ."}}
       (Tự tính tổng tiền trong response_speech).
    3. Khi khách chào tạm biệt/kết thúc, trả về JSON:
       {{"end_conversation": true, "response_speech": "Dạ cảm ơn."}}
    4. Không giải thích JSON, chỉ trả về JSON hoặc Text.
    """

@app.route("/process-command", methods=["POST"])
def handle_command():
    try:
        update_activity()
        data = request.json
        history = data.get("history", []) 
        messages = [{"role": "system", "content": build_system_prompt()}] + history
        
        headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
        body = {"model": "openai/gpt-3.5-turbo", "messages": messages}
        
        resp = requests.post(OPENROUTER_ENDPOINT, headers=headers, json=body).json()
        
        if "error" in resp:
            return jsonify({"actions": [], "response_speech": "Lỗi AI Key."})

        content = resp["choices"][0]["message"]["content"].strip()
        
        # Xử lý JSON từ AI
        if content.startswith("{"):
            try:
                return jsonify(json.loads(content))
            except: pass
            
        return jsonify({"actions": [], "response_speech": content})
    except Exception as e:
        print(f"Lỗi Chat: {e}")
        return jsonify({"actions": [], "response_speech": "Lỗi hệ thống."})

# ==============================================================================
# 5. API ĐIỀU KHIỂN ROBOT (Gửi lệnh sang ESP8266)
# ==============================================================================

def send_to_robot(script_id):
    """Gửi HTTP POST sang ESP8266"""
    try:
        # Gửi dữ liệu dưới dạng form-data (key='plain')
        command_json = json.dumps({"command": str(script_id)})
        payload = {'plain': command_json}
        
        print(f"Đang gửi kịch bản [{script_id}] tới Robot...")
        
        # Timeout 5s (Vì ESP code mới sẽ trả lời ngay lập tức)
        response = requests.post(ESP_ROBOT_URL, data=payload, timeout=5)
        
        if response.status_code == 200:
            print(f"Robot đã nhận lệnh: {response.text}")
            return True
        else:
            print(f"Robot kết nối được nhưng báo lỗi: {response.status_code}")
            # Vẫn trả về True để App không báo lỗi (vì lệnh đã tới ESP rồi)
            return True 
    except Exception as e:
        print(f"Lỗi kết nối Robot (ESP tắt/Sai IP?): {e}")
        return False

@app.route("/execute-order", methods=["POST"])
def execute_order():
    """Flutter gọi API này sau khi thanh toán thành công"""
    try:
        update_activity()
        data = request.json
        # App gửi: {"item_ids": ["c1", "c3"]}
        item_ids = data.get("item_ids", []) 
        
        if not item_ids:
            # Fallback cho app cũ
            item_ids = data.get("items", [])

        print(f"Nhận đơn hàng cần pha chế: {item_ids}")
        
        if not item_ids:
            return jsonify({"success": False, "message": "Giỏ hàng trống"}), 400

        # Gửi lệnh lần lượt cho từng món
        for index, item_id in enumerate(item_ids):
            script_id = SCRIPT_MAPPING.get(item_id)
            if script_id:
                success = send_to_robot(script_id)
                if not success:
                    # Nếu mất kết nối hoàn toàn mới báo lỗi
                    return jsonify({"success": False, "message": f"Mất kết nối Robot khi pha món {item_id}"}), 500
                
                # [QUAN TRỌNG] Nếu có nhiều món, nghỉ 2s giữa các lệnh 
                # để Arduino Mega kịp xử lý Serial Buffer
                if index < len(item_ids) - 1:
                    time.sleep(2)
            else:
                print(f"Món {item_id} chưa được lập trình cho Robot")

        # [QUAN TRỌNG] Trả về format chuẩn để Flutter hiểu là thành công
        return jsonify({
            "success": True, 
            "status": "success",
            "message": "Đã gửi đơn hàng xuống Robot"
        }), 200

    except Exception as e:
        print(f"Lỗi Server Execute: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

# ==============================================================================
# 6. KHỞI CHẠY SERVER
# ==============================================================================
if __name__ == "__main__":
    print("--------------------------------------------------")
    print(f"Server đang chạy tại: 0.0.0.0:5000")
    print(f"Robot Endpoint: {ESP_ROBOT_URL}")
    print("--------------------------------------------------")
    app.run(host="0.0.0.0", port=5000, debug=True)