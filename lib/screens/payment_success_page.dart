// --- lib/screens/payment_success_page.dart ---
import 'package:flutter/material.dart';
import 'dart:async'; // Import để dùng Timer
import 'package:provider/provider.dart';
import 'package:cafe_robot/providers/cart_provider.dart';
import 'package:cafe_robot/api_service.dart';

// 1. Định nghĩa các trạng thái của trang
enum OrderStatus {
  Paid,     // Vừa thanh toán xong (chờ 3s)
  Sending,  // Đang gửi lệnh (trong khi đếm ngược)
  Brewing,  // Robot đang pha chế (trong khi đếm ngược)
  Ready,    // Pha chế xong
  Error     // Gặp lỗi
}

class PaymentSuccessPage extends StatefulWidget {
  const PaymentSuccessPage({super.key});

  @override
  State<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<PaymentSuccessPage>
    with SingleTickerProviderStateMixin {

  // --- Quản lý trạng thái ---
  OrderStatus _status = OrderStatus.Paid; // Bắt đầu ở trạng thái "Đã thanh toán"
  final ApiService _apiService = ApiService();
  String _errorMessage = "";

  // --- Timer & Animation ---
  Timer? _countdownTimer;
  int _countdownSeconds = 180; // Thời gian pha chế
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Bắt đầu luồng
    _startPaymentFlow();
  }

  void _startPaymentFlow() {
    // 1. Bắt đầu ở trạng thái Paid, đợi 3 giây "ăn mừng"
    setState(() {
      _status = OrderStatus.Paid;
    });

    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      // 2. SAU 3 GIÂY: BẮT ĐẦU ĐẾM NGƯỢC VÀ GỬI LỆNH CÙNG LÚC
      setState(() {
        _status = OrderStatus.Sending; // Chuyển sang "Đang gửi"
      });
      _startBrewingCountdown(); // Bắt đầu 180s
      _sendToRobot();           // Gửi lệnh (hàm async này sẽ tự chạy ngầm)
    });
  }

  Future<void> _sendToRobot() async {
    final cart = Provider.of<CartProvider>(context, listen: false);
    if (!mounted) return;
    final List<String> itemIds = cart.items.map((item) => item.id).toList();

    try {
      final bool success = await _apiService.executeOrder(itemIds);

      if (success && mounted) {
        // 3A. Gửi lệnh THÀNH CÔNG
        cart.clearCart(); // Xóa giỏ hàng
        // Đồng hồ vẫn đang chạy, chỉ đổi trạng thái
        setState(() {
          _status = OrderStatus.Brewing;
        });
      } else if (mounted) {
        // 3B. Gửi lệnh THẤT BẠI
        setState(() {
          _status = OrderStatus.Error;
          _errorMessage = 'Lỗi Robot: Không thể gửi lệnh pha chế. Vui lòng thử lại.';
        });
        _countdownTimer?.cancel(); // Dừng đếm ngược nếu lỗi
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = OrderStatus.Error;
          _errorMessage = 'Lỗi Mạng: Không thể kết nối tới server.';
        });
        _countdownTimer?.cancel(); // Dừng đếm ngược nếu lỗi
      }
    }
  }

  // Hàm này giờ CHỈ bắt đầu đếm ngược
  void _startBrewingCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 0) {
        if (mounted) {
          setState(() {
            _countdownSeconds--;
          });
        }
      } else {
        // --- HẾT GIỜ ---
        _countdownTimer?.cancel();
        // Chỉ đổi trạng thái nếu robot không báo lỗi trước đó
        if (mounted && _status != OrderStatus.Error) {
          setState(() {
            _status = OrderStatus.Ready; // Pha chế xong
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  // --- GIAO DIỆN CHÍNH ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: _buildBodyForStatus(),
        ),
      ),
    );
  }

  // --- CÁC HÀM BUILD UI ---

  String _getAppBarTitle() {
    switch (_status) {
      case OrderStatus.Paid:
        return 'Thanh toán thành công!';
      case OrderStatus.Sending:
      case OrderStatus.Brewing:
        return 'Robot đang pha chế...';
      case OrderStatus.Ready:
        return 'Đơn hàng sẵn sàng!';
      case OrderStatus.Error:
        return 'Đã xảy ra lỗi!';
    }
  }

  Widget _buildBodyForStatus() {
    switch (_status) {
      case OrderStatus.Paid:
        return _buildStatusView(
          icon: Icons.check_circle,
          iconColor: Colors.green,
          message: 'Đã thanh toán thành công!',
          subMessage: 'Đang chuẩn bị gửi lệnh cho robot...',
          showLoading: true,
        );
    // Gộp 2 trạng thái này lại, vì cả 2 đều hiển thị đồng hồ đếm ngược
      case OrderStatus.Sending:
      case OrderStatus.Brewing:
        return _buildBrewingView();
      case OrderStatus.Ready:
        return _buildOrderReadyView();
      case OrderStatus.Error:
        return _buildErrorView();
    }
  }

  // UI Chung (Cho trạng thái Paid)
  Widget _buildStatusView({
    required IconData icon,
    required Color iconColor,
    required String message,
    String? subMessage,
    bool showLoading = false,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: iconColor, size: 100),
        const SizedBox(height: 20),
        Text(
          message,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        if (subMessage != null) const SizedBox(height: 15),
        if (subMessage != null)
          Text(
            subMessage,
            style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
            textAlign: TextAlign.center,
          ),
        if (showLoading) const SizedBox(height: 30),
        if (showLoading) const CircularProgressIndicator(),
      ],
    );
  }

  // UI Pha chế (quay + đếm ngược)
  Widget _buildBrewingView() {
    // Hiển thị text khác nhau tùy theo trạng thái
    String message = (_status == OrderStatus.Sending)
        ? 'Đang gửi lệnh cho Robot...'
        : 'Robot đang pha chế...';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RotationTransition(
          turns: _animationController,
          child: Icon(
            Icons.settings,
            color: Colors.brown.shade700,
            size: 100,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          message, // <-- Dùng text động
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 30),
        const Text(
          'Vui lòng chờ trong:',
          style: TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          _formatDuration(_countdownSeconds), // <-- Đồng hồ đếm ngược
          style: TextStyle(
            fontSize: 60,
            fontWeight: FontWeight.bold,
            color: Colors.brown.shade700,
          ),
        ),
      ],
    );
  }

  // UI Lấy hàng
  Widget _buildOrderReadyView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.coffee, color: Colors.brown.shade700, size: 100),
        const SizedBox(height: 20),
        const Text('Đơn hàng của bạn đã sẵn sàng!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 30),
        const Text('Vui lòng đến quầy nhận đồ uống.\nCảm ơn quý khách!', style: TextStyle(fontSize: 18), textAlign: TextAlign.center),
        const SizedBox(height: 40),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.brown, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            textStyle: const TextStyle(fontSize: 18),
          ),
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: const Text('Về trang chủ'),
        )
      ],
    );
  }

  // UI Lỗi
  Widget _buildErrorView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStatusView(
          icon: Icons.error_outline,
          iconColor: Colors.red,
          message: 'Đã xảy ra lỗi!',
          subMessage: _errorMessage,
          showLoading: false,
        ),
        const SizedBox(height: 30),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade700, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            textStyle: const TextStyle(fontSize: 18),
          ),
          onPressed: () {
            // Quay về giỏ hàng (không xóa giỏ hàng)
            Navigator.of(context).pop();
          },
          child: const Text('Quay lại giỏ hàng'),
        )
      ],
    );
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor().toString().padLeft(2, '0');
    final remainingSeconds = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainingSeconds';
  }
}