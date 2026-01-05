import serial
import time
import re

# Chọn đúng cổng COM của ESP8266 (ví dụ: COM9 trên Windows hoặc /dev/ttyUSB0 trên Linux)
port = "COM9"
baud = 9600

try:
    ser = serial.Serial(port, baud, timeout=2)
    print(f"Đang đọc dữ liệu từ {port}...")

    time.sleep(2)  # đợi ESP khởi động

    while True:
        line = ser.readline().decode(errors='ignore').strip()
        if line:
            print(line)
            # Nếu dòng chứa địa chỉ IP, trích xuất ra
            if "IP:" in line:
                ip_match = re.search(r"IP:(\d+\.\d+\.\d+\.\d+)", line)
                if ip_match:
                    esp_ip = ip_match.group(1)
                    print(f"\n✅ Địa chỉ IP của ESP8266 là: {esp_ip}")
                    break

except serial.SerialException:
    print("❌ Không thể mở cổng serial. Kiểm tra lại COM port và kết nối.")
