// --- lib/api_service.dart ---
import 'dart:convert';
import 'package:http/http.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // --- CẤU HÌNH ---
  // SỬA ĐỊA CHỈ NÀY NẾU BẠN KHÔNG DÙNG ANDROID EMULATOR
  final String _baseUrl = "http://192.168.1.136:5000";
  // --- KẾT THÚC CẤU HÌNH ---

  // 1. Hàm gửi tin nhắn và nhận phản hồi từ AI (GIỮ NGUYÊN)
  Future<Map<String, dynamic>> sendMessage(List<Map<String, String>> history) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/process-command"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "history": history,
        }),
      );

      if (response.statusCode == 200) {
        final String responseBody = utf8.decode(response.bodyBytes);
        return jsonDecode(responseBody);
      } else {
        return {
          "actions": [],
          "response_speech": "Lỗi server: ${response.statusCode}. Vui lòng thử lại."
        };
      }
    } catch (e) {
      print("LỖI KẾT NỐI: $e");
      return {
        "actions": [],
        "response_speech": "Ôi, không thể kết nối tới server AI. Bạn kiểm tra lại nhé."
      };
    }
  }

  // 2. Gửi đơn hàng đã thanh toán cho robot (GIỮ NGUYÊN)
  Future<bool> executeOrder(List<String> itemIds) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/execute-order"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "item_ids": itemIds,
        }),
      );

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
        return responseBody['status'] == 'success';
      } else {
        print("Lỗi khi gửi lệnh executeOrder: ${response.body}");
        return false;
      }
    } catch (e) {
      print("Lỗi mạng khi executeOrder: $e");
      return false;
    }
  }

  // 3. Điều khiển góc quay thủ công (GIỮ NGUYÊN)
  Future<bool> sendManualAngles(List<double> angles) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/manual-control"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "angles": angles,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Lỗi mạng khi sendManualAngles: $e");
      return false;
    }
  }

  // 4. Điều khiển Inverse Kinematics (GIỮ NGUYÊN)
  Future<List<double>?> sendInverseKinematics(double x, double y, double z) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/inverse-kinematics"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "x": x,
          "y": y,
          "z": z
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        List<dynamic> anglesList = data['sent_angles'];
        return anglesList.map((angle) => angle as double).toList();
      } else {
        return null;
      }
    } catch (e) {
      print("Lỗi mạng khi sendInverseKinematics: $e");
      return null;
    }
  }

  // --- [MỚI] 5. Kiểm tra xem có khách đến hay không (Polling) ---
  // Hàm này sẽ gọi endpoint /check-arrival mà bạn đã thêm vào server.py
  Future<bool> checkGuestArrival() async {
    try {
      final response = await http.get(
        Uri.parse("$_baseUrl/check-arrival"),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Server trả về: {"should_greet": true} hoặc {"arrived": true} tùy cách bạn đặt tên bên Python
        // Ở đây ta kiểm tra cả 2 trường hợp cho chắc
        return (data['arrived'] == true) || (data['should_greet'] == true);
      }
      return false;
    } catch (e) {
      // Lỗi mạng khi polling là bình thường (ví dụ server tắt), chỉ cần return false
      return false;
    }
  }
}