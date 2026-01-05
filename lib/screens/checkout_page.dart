// --- lib/screens/checkout_page.dart ---
import 'package:flutter/material.dart';
import 'dart:async'; // Import thư viện 'async'
import 'package:cafe_robot/screens/payment_success_page.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {

  @override
  void initState() {
    super.initState();
    // Bắt đầu quá trình giả lập thanh toán
    _simulatePayment();
  }

  Future<void> _simulatePayment() async {
    // 1. Giả lập 3 giây quét QR và "xác nhận" thanh toán
    await Future.delayed(const Duration(seconds: 3));

    // 2. Chuyển sang trang thành công (KHÔNG gửi lệnh, KHÔNG xóa giỏ hàng)
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const PaymentSuccessPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Giao diện giữ nguyên như cũ, chỉ hiển thị QR và vòng xoay
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đang xử lý...'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Quét mã QR để thanh toán',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Image.asset(
                'images/qr.jpg',
                width: 300,
                height: 300,
              ),
              const SizedBox(height: 30),
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              const Text(
                'Đang chờ xác nhận thanh toán...',
                style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}