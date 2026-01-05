// --- lib/providers/cart_provider.dart ---
import 'package:flutter/material.dart';
import 'package:cafe_robot/models/coffee.dart'; // Cập nhật import

class CartProvider with ChangeNotifier {
  final List<Coffee> _items = [];

  // --- LOGIC VOUCHER MỚI ---
  final String _validVoucherCode = "UET_ENDYEAR"; // Mã 100%
  final double _voucherDiscountPercent = 1.0; // 1.0 = 100%
  String? _appliedVoucherCode;
  // --- KẾT THÚC LOGIC MỚI ---

  // --- Getters ---
  List<Coffee> get items => _items;
  String? get appliedVoucherCode => _appliedVoucherCode;

  // Tạm tính (chưa giảm giá)
  double get subtotal {
    var total = 0.0;
    for (var item in _items) {
      total += item.price;
    }
    return total;
  }

  // SỐ tiền được giảm
  double get discountAmount {
    if (_appliedVoucherCode == _validVoucherCode) {
      return subtotal * _voucherDiscountPercent;
    }
    return 0.0;
  }

  // Tổng tiền (đã giảm giá)
  double get totalAmount {
    // Đảm bảo tổng tiền không bao giờ âm
    final total = subtotal - discountAmount;
    return total < 0.0 ? 0.0 : total;
  }

  // --- Methods ---

  // Hàm thêm sản phẩm
  void addItem(Coffee coffee) {
    _items.add(coffee);
    notifyListeners();
  }

  // Xóa giỏ hàng (reset cả voucher)
  void clearCart() {
    _items.clear();
    _appliedVoucherCode = null;
    notifyListeners();
  }

  // --- HÀM VOUCHER MỚI ---

  // Áp dụng voucher
  // Trả về message thành công hoặc thất bại
  String applyVoucher(String code) {
    // Chuẩn hóa code (xóa cách, viết hoa)
    final trimmedCode = code.trim().toUpperCase();

    if (trimmedCode == _validVoucherCode) {
      _appliedVoucherCode = trimmedCode;
      notifyListeners();
      return "Áp dụng voucher thành công! Bạn được giảm 100%.";
    } else {
      return "Mã voucher không hợp lệ hoặc đã hết hạn.";
    }
  }

  // Xóa voucher
  void removeVoucher() {
    _appliedVoucherCode = null;
    notifyListeners();
  }
}