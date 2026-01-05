import os
import requests
from flask import Flask, request, jsonify
from dotenv import load_dotenv
import json
from flask_cors import CORS
from pathlib import Path # Dùng để tìm .env

# --- 1. CÀI ĐẶT ---
app = Flask(__name__)
CORS(app) # Cho phép Flutter Web/Mobile gọi

# Tải file .env một cách an toàn
try:
    script_dir = Path(__file__).resolve().parent
    dotenv_path = script_dir / '.env'
    load_dotenv(dotenv_path=dotenv_path)
    print(f"Đã tải file .env từ: {dotenv_path}")
except Exception as e:
    print(f"Lỗi khi tìm .env: {e}")

# Lấy API Key
api_key = os.getenv("OPENROUTER_API_KEY")
if not api_key:
    raise ValueError("OPENROUTER_API_KEY không tìm thấy. Hãy kiểm tra file .env.")

# Endpoint của OpenRouter
OPENROUTER_ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"


# --- BỔ SUNG 1: Cấu hình Robot ---
# ⚠️ !!! QUAN TRỌNG: Thay đổi IP này thành địa chỉ IP của vi xử lý (ESP32, RPi...)
MICROCONTROLLER_API_ENDPOINT = "http://192.168.1.100/run-script" 

# Mapping ID sản phẩm sang ID kịch bản của robot
# (Hãy đảm bảo các ID này khớp với file coffee_provider.dart)
SCRIPT_MAPPING = {
    "c1": 1, # cà phê sữa nóng
    "c2": 2, # matcha latte nóng
    "c3": 3, # trà đào nóng
    "c4": 4  # trà dâu nóng
    # Thêm các món khác nếu cần
}
# --- KẾT THÚC BỔ SUNG 1 ---


# --- 2. HÀM PROMPT (Bộ não chính) ---
def build_system_prompt():
    # Sửa menu của bạn tại đây - THÊM "price"
    menu = """
    [
        {"id": "c1", "name": "cà phê sữa nóng", "price": 30000},
        {"id": "c2", "name": "matcha latte nóng", "price": 25000},
        {"id": "c3", "name": "trà đào nóng", "price": 25000},
        {"id": "c4", "name": "trà dâu nóng", "price": 20000}
    ]
    """
    
    # Prompt huấn luyện AI
    return f"""
    Bạn là "Phương", một nhân viên nhận đơn hàng qua giọng nói tại quán cà phê.
    Hãy luôn thân thiện, chuyên nghiệp và nói chuyện tự nhiên (ví dụ: "dạ", "vâng ạ").
    Menu của quán (bao gồm cả giá): {menu}

    --- QUY TẮC CỦA BẠN ---
    1.  **NÓI CHUYỆN BÌNH THƯỜNG (TEXT):**
        * Khi chào hỏi, hỏi thêm, hoặc xác nhận từng món, BẠN CHỈ TRẢ LỜI BẰNG TEXT THƯỜNG.
        * Ví dụ: "Vâng ạ, bạn cần gì nữa không ạ? bên mình còn các món khác như trà dâu nóng cũng rất ngon đấy ạ! hoặc 1 món khác không phải món họ gọi trước đó"
        * Nếu khách nói chuyện phiếm hoặc chuyện không liên quan đến order, hãy nói chuyện bình thường và chèn 1 số câu ca dao khiến họ bất ngờ và gây sự hứng thú cho họ
    
    2.  **CHỐT ĐƠN (JSON ACTIONS):**
        * Khi khách hàng đã order xong và bạn muốn TỔNG KẾT đơn hàng (ví dụ khách nói "đủ rồi"), BẠN PHẢI TRẢ LỜI BẰNG MỘT KHỐI JSON.
        * JSON này phải chứa *toàn bộ* các món khách đã gọi trong `actions` và một `response_speech`.
        * **QUAN TRỌNG:** Trong `response_speech`, bạn phải dùng `menu` để tính **tổng tiền** của tất cả các món trong `actions` và báo giá cho khách (ví dụ: 80.000 đồng).
        * **JSON MẪU (ĐÃ CẬP NHẬT):** {{"actions": [{{"item_id": "c1", "quantity": 1}}, {{"item_id": "c3", "quantity": 2}}], "response_speech": "Của bạn 1 cà phê sữa nóng và 2 trà đào nóng, tổng cộng là 80.000 đồng. Mình gửi bạn giỏ hàng để tiến hành thanh toán nhé nhé!"}}

    3.  **KẾT THÚC (JSON END):**
        * Khi khách hàng nói "tạm biệt", "cảm ơn", BẠN PHẢI TRẢ LỜI BẰNG JSON chứa `end_conversation`.
        * JSON Mẫu: {{"end_conversation": true, "response_speech": "Cảm ơn bạn. Hẹn gặp lại!"}}
    
    4.  **XỬ LÝ ĐỒ LẠNH/ĐÁ (QUAN TRỌNG):**
        * Menu của quán *chỉ có đồ nóng* như đã liệt kê.
        * Nếu khách hỏi mua đồ lạnh, đồ đá, hãy lịch sự trả lời rằng quán **đã hết** hoặc **hiện chỉ phục vụ đồ nóng**.
        * Luôn gợi ý họ chuyển sang dùng món nóng tương ứng.

    Đừng bao giờ thêm ```json hay giải thích. Chỉ trả lời text thường, hoặc JSON.
    """

# --- BỔ SUNG 2: Hàm gửi lệnh cho vi xử lý ---
def send_to_robot(script_id):
    """
    Gửi một lệnh POST tới vi xử lý để chạy một kịch bản.
    """
    try:
        # Vi xử lý của bạn cần nhận 1 JSON ví dụ: {"script_id": 1}
        payload = {"script_id": script_id}
        
        # Gọi đến IP của robot với timeout 5 giây
        response = requests.post(MICROCONTROLLER_API_ENDPOINT, json=payload, timeout=5) 
        
        if response.status_code == 200:
            print(f"🤖 Robot đã nhận và xác nhận kịch bản: {script_id}")
            return True
        else:
            print(f"❌ Lỗi khi gửi lệnh cho Robot (Mã: {response.status_code}): {response.text}")
            return False
    except requests.exceptions.RequestException as e:
        # Lỗi (ví dụ: robot offline, sai IP, timeout)
        print(f"❌ KHÔNG THỂ KẾT NỐI VỚI ROBOT: {e}")
        return False
# --- KẾT THÚC BỔ SUNG 2 ---


# --- 3. API ENDPOINT (Flutter sẽ gọi) ---
@app.route("/process-command", methods=["POST"])
def handle_command():
    try:
        data = request.json
        history = data.get("history", []) 
        
        if not history:
            return jsonify({"error": "Không có lịch sử"}), 400
        
        print(f" Flutter gửi ({len(history)} tin nhắn): {history[-1]['content']}")

        messages = [
            {"role": "system", "content": build_system_prompt()}
        ]
        messages.extend(history) 

        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        body = {
            "model": "openai/gpt-3.5-turbo", # Bạn có thể đổi model (ví dụ: google/gemini-1.5-pro)
            "messages": messages, 
            "temperature": 0.7 # Tăng nhẹ temp để AI sáng tạo hơn với ca dao
        }
        
        resp = requests.post(OPENROUTER_ENDPOINT, headers=headers, json=body)
        resp_json = resp.json()
        
        # --- SỬA LỖI 'choices' ---
        # 1. Kiểm tra xem OpenRouter có trả về LỖI không
        if "error" in resp_json:
            error_message = resp_json["error"].get("message", "Lỗi không xác định")
            print(f"❌ LỖI TỪ OPENROUTER: {error_message}")
            return jsonify({
                "actions": [],
                "response_speech": f"Hệ thống AI gặp lỗi: {error_message}"
            })

        # 2. Nếu không có lỗi, mới tiếp tục xử lý "choices"
        if "choices" not in resp_json or not resp_json["choices"]:
            print(f"❌ LỖI: OpenRouter không trả về 'choices'.")
            return jsonify({
                "actions": [],
                "response_speech": "Lỗi: AI không trả về nội dung."
            })
        # --- KẾT THÚC SỬA LỖI ---
            
        content = resp_json["choices"][0]["message"]["content"].strip()
        print(f" AI trả về: {content}")

        # --- Phân tích trả lời của AI ---
        if content.startswith("{"):
            try:
                result_json = json.loads(content)
                return jsonify(result_json)
            except json.JSONDecodeError:
                return jsonify({"actions": [], "response_speech": "Tôi lỡ lời, bạn nói lại giúp tôi nhé."})
        
        else:
            return jsonify({
                "actions": [], 
                "response_speech": content
            })

    except Exception as e:
        print(f"❌ LỖI SERVER KHI CHAT: {e}")
        return jsonify({
            "actions": [],
            "response_speech": f"Hệ thống AI gặp lỗi: {e}"
        })

# --- BỔ SUNG 3: Endpoint để Flutter kích hoạt pha chế ---
@app.route("/execute-order", methods=["POST"])
def execute_order():
    """
    Nhận đơn hàng từ Flutter SAU KHI thanh toán thành công.
    Flutter sẽ gửi 1 JSON chứa danh sách các ID đã lặp lại:
    Ví dụ: {"item_ids": ["c1", "c1", "c3"]} 
    (Tương ứng 2 cà phê sữa, 1 trà đào)
    """
    try:
        data = request.json
        item_ids = data.get("item_ids", []) # Nhận danh sách ID từ Flutter
        
        if not item_ids:
            return jsonify({"error": "Không có đơn hàng"}), 400

        print(f"🔥 Nhận lệnh thực thi đơn hàng: {item_ids}")
        
        execution_log = [] # Ghi lại log
        
        # Lặp qua từng ID món hàng
        # (Flutter đã gửi ["c1", "c1", "c3"] nên ta chỉ cần lặp)
        for item_id in item_ids:
            script_id = SCRIPT_MAPPING.get(item_id)
            
            if script_id:
                print(f"🚀 Gửi kịch bản {script_id} (cho món {item_id})")
                success = send_to_robot(script_id)
                
                if not success:
                    # Nếu robot thất bại, dừng lại và báo lỗi ngay
                    execution_log.append(f"Lỗi khi thực thi kịch bản {script_id} cho {item_id}")
                    return jsonify({"status": "error", "message": f"Không thể gửi lệnh {script_id} tới robot."}), 500
                    
                execution_log.append(f"Đã gửi kịch bản {script_id} cho {item_id}")
            else:
                print(f"⚠️ Bỏ qua item_id không xác định: {item_id}")
                execution_log.append(f"Bỏ qua {item_id} không có kịch bản")

        # Nếu mọi thứ thành công
        print("✅ Đã gửi tất cả kịch bản cho robot.")
        return jsonify({"status": "success", "message": "Đã gửi tất cả lệnh pha chế cho robot.", "log": execution_log})

    except Exception as e:
        print(f"❌ LỖI SERVER KHI THỰC THI: {e}")
        return jsonify({"status": "error", "message": f"Lỗi server khi thực thi: {e}"}), 500
# --- KẾT THÚC BỔ SUNG 3 ---


# --- 4. CHẠY SERVER ---
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)