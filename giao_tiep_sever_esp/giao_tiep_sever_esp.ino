/*
 * CODE ESP8266: FIX LỖI TIMEOUT + RESET TRẠNG THÁI TỰ ĐỘNG
 * * Logic:
 * 1. Nhận JSON từ Python -> Gửi Serial xuống Mega.
 * 2. Phản hồi HTTP 200 OK ngay lập tức (để App Flutter không báo lỗi).
 * 3. Dùng hàm loop() để lắng nghe phản hồi từ Mega (STEP/DONE).
 * 4. Khi xong (DONE) -> Tự động chuyển trạng thái về "Sẵn sàng".
 */

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ArduinoJson.h>

// ============================================================
// 1. CẤU HÌNH WIFI & MẠNG
// ============================================================
const char* ssid = "Repeater-E024";      
const char* password = "1234512345"; 

// IP Tĩnh (Phải trùng với cấu hình trong sever.py)
IPAddress staticIP(192, 168, 1, 100);
IPAddress gateway(192, 168, 1, 1);
IPAddress subnet(255, 255, 255, 0);

ESP8266WebServer server(80);

// Biến toàn cục lưu trạng thái để hiển thị Web
String currentStatus = "SAN SANG (READY)"; 
String currentStep = "Cho don hang moi...";

// ============================================================
// 2. HÀM XỬ LÝ LỆNH TỪ PYTHON (/run-command)
// ============================================================
void handleCommand() {
  // A. Kiểm tra dữ liệu
  if (!server.hasArg("plain")) {
    server.send(400, "text/plain", "No Data");
    return;
  }
  
  String jsonString = server.arg("plain");
  StaticJsonDocument<200> doc;
  DeserializationError error = deserializeJson(doc, jsonString);
  
  if (error) {
    server.send(400, "text/plain", "Invalid JSON");
    return;
  }
  
  const char* command = doc["command"];
  
  if (command) {
    // 1. Gửi lệnh xuống Arduino Mega
    // Xóa sạch bộ đệm Serial cũ để tránh đọc nhầm dữ liệu rác
    while(Serial.available()) Serial.read(); 
    Serial.println(command); 

    // 2. Cập nhật trạng thái Web ngay lập tức
    currentStatus = "DANG PHA CHE (KICH BAN " + String(command) + ")";
    currentStep = "Da gui lenh xuong Robot...";

    // 3. [QUAN TRỌNG] PHẢN HỒI NGAY LẬP TỨC CHO PYTHON
    // Để App Flutter nhận được Success ngay và bắt đầu đếm ngược, không bị lỗi
    server.send(200, "application/json", "{\"status\":\"ok\",\"message\":\"Command sent to Robot\"}");
  } else {
    server.send(400, "text/plain", "Command Missing");
  }
}

// ============================================================
// 3. HÀM LẮNG NGHE MEGA (CHẠY LIÊN TỤC TRONG LOOP)
// ============================================================
void checkMegaStatus() {
  // Hàm này sẽ chạy liên tục để "nghe ngóng" Arduino Mega
  while (Serial.available()) {
    String receivedLine = Serial.readStringUntil('\n');
    receivedLine.trim(); // Xóa khoảng trắng thừa (xuống dòng)

    if (receivedLine.length() > 0) {
      
      // TRƯỜNG HỢP A: Nhận thông tin bước đi (STEP:...)
      if (receivedLine.startsWith("STEP:")) {
        currentStep = receivedLine.substring(5); // Cắt bỏ chữ "STEP:" lấy nội dung
        currentStatus = "DANG PHA CHE...";
      } 
      
      // TRƯỜNG HỢP B: Nhận tín hiệu hoàn thành (DONE)
      else if (receivedLine == "DONE") {
        // [QUAN TRỌNG] Reset trạng thái về Sẵn sàng đợi lệnh tiếp theo
        currentStatus = "SAN SANG (READY)";
        currentStep = "Cho don hang moi...";
      }
    }
  }
}

// ============================================================
// 4. GIAO DIỆN WEB GIÁM SÁT (MONITOR)
// ============================================================
void handleRoot() {

  // Tự động reload mỗi 1 giây để cập nhật bước đi

  String html = "<html><head><title>Robot Monitor</title>";

  html += "<meta http-equiv='refresh' content='1'>";

  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";

  html += "<style>";

  html += "body { font-family: Arial, sans-serif; text-align: center; background-color: #f0f2f5; margin: 0; padding: 20px; }";

  html += ".card { background: white; max-width: 500px; margin: auto; padding: 30px; border-radius: 15px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }";

  html += "h1 { color: #333; }";

  html += ".status { font-size: 24px; font-weight: bold; color: #007bff; margin: 20px 0; }";

  html += ".step { font-size: 20px; color: #28a745; background: #e6fffa; padding: 15px; border-radius: 8px; border: 1px solid #b2f5ea; }";

  html += ".ip { color: #888; font-size: 14px; margin-top: 20px; }";

  html += "</style></head><body>";

 

  html += "<div class='card'>";

  html += "<h1>ROBOT CAFE MONITOR</h1>";

  html += "<div class='status'>" + currentStatus + "</div>";

  html += "<div class='step'>Running Step:<br><b>" + currentStep + "</b></div>";

  html += "<div class='ip'>Device IP: " + WiFi.localIP().toString() + "</div>";

  html += "</div>";

 

  html += "</body></html>";

  server.send(200, "text/html", html);

}



// ============================================================
// 5. SETUP & LOOP
// ============================================================
void setup() {
  // Tốc độ Serial phải khớp với Arduino Mega
  Serial.begin(115200);
  
  // Cấu hình LED báo trạng thái
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, HIGH); 

  // Kết nối Wifi
  WiFi.config(staticIP, gateway, subnet);
  WiFi.begin(ssid, password);
  
  // Chờ kết nối
  while (WiFi.status() != WL_CONNECTED) {
    delay(250);
    digitalWrite(LED_BUILTIN, !digitalRead(LED_BUILTIN));
  }
  digitalWrite(LED_BUILTIN, LOW); // Đèn sáng = Có Wifi

  // Khởi chạy Server
  server.on("/", HTTP_GET, handleRoot);
  server.on("/run-command", HTTP_POST, handleCommand);
  server.begin();
}

void loop() {
  // 1. Xử lý các yêu cầu Web (từ App hoặc Trình duyệt)
  server.handleClient();
  
  // 2. Lắng nghe Arduino Mega liên tục để cập nhật trạng thái
  checkMegaStatus();

  // 3. Tự động kết nối lại Wifi nếu bị rớt mạng
  if (WiFi.status() != WL_CONNECTED) {
    digitalWrite(LED_BUILTIN, HIGH);
    WiFi.reconnect();
  } else {
    digitalWrite(LED_BUILTIN, LOW);
  }
}