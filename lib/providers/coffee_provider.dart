// --- lib/providers/coffee_provider.dart ---
import 'package:flutter/material.dart';
import 'package:cafe_robot/models/coffee.dart'; // Cập nhật import

class CoffeeProvider with ChangeNotifier {
  // Danh sách cà phê
  final List<Coffee> _coffees = [
    Coffee(
      id: 'c1',
      name: 'cà phê sữa',
      image: 'images/caphesua.jpg',
      price: 30000,
      description: 'Cà phê đậm đà được pha từ hạt rang xay nguyên chất, kết hợp cùng sữa đặc béo ngậy, mang đến hương vị truyền thống đặc trưng của Việt Nam. Thức uống lý tưởng để khởi đầu ngày mới tràn đầy năng lượng.',
      taste: 'Đậm, béo, thơm ngọt',
      suitable: 'Buổi sáng – khi cần tỉnh táo và tập trung',
    ),
    Coffee(
      id: 'c2',
      name: 'matcha late',
      image: 'images/matcha.jpg',
      price: 25000,
      description: 'Hòa quyện giữa bột matcha nguyên chất từ Nhật Bản và sữa tươi thanh béo, tạo nên hương vị tươi mát, nhẹ nhàng nhưng vẫn đậm đà. Một lựa chọn hoàn hảo cho những ai yêu thích hương vị tự nhiên và thanh khiết.',
      taste: 'Thanh, béo nhẹ, thơm mùi trà xanh',
      suitable: 'Buổi chiều thư giãn hoặc học tập, làm việc',
    ),
    Coffee(
      id: 'c3',
      name: 'trà đào cam sả',
      image: 'images/tradao.jpg',
      price: 25000,
      description: 'Sự kết hợp hài hòa giữa trà ô long thanh mát, vị đào ngọt dịu, cam tươi và hương sả thoang thoảng. Thức uống giải khát tuyệt vời, mang lại cảm giác sảng khoái ngay từ ngụm đầu tiên.',
      taste: 'Chua ngọt, mát lạnh, thơm hương đào – cam – sả',
      suitable: 'Ngày nắng nóng hoặc khi cần làm mới vị giác',
    ),
    Coffee(
      id: 'c4',
      name: 'trà dâu',
      image: 'images/tradau.jpg',
      price: 20000,
      description: 'Trà tươi được pha cùng siro dâu tự nhiên và những lát dâu mọng nước, tạo nên hương vị ngọt ngào, chua nhẹ và vô cùng cuốn hút. Một lựa chọn không thể bỏ qua cho những ai yêu thích sự tươi mát và trẻ trung.',
      taste: 'Ngọt dịu, chua thanh, thơm mùi dâu tây',
      suitable: 'Mọi thời điểm trong ngày',
    ),

    // --- 6 MÓN SẮP RA MẮT ---
    // (Bạn có thể sửa tên 'name' tùy ý)
    Coffee(
      id: 'c5',
      name: 'Cà Phê Muối',
      image: 'images/caphemuoi.jpg', // Ảnh này sẽ không hiển thị
      price: 0,
      description: 'COMING_SOON', // Đây là "cờ" quan trọng
      taste: '',
      suitable: '',
    ),
    Coffee(
      id: 'c6',
      name: 'Trà Sữa Olong',
      image: 'images/olong.jpg',
      price: 0,
      description: 'COMING_SOON',
      taste: '',
      suitable: '',
    ),
    Coffee(
      id: 'c7',
      name: 'Cold Brew',
      image: 'images/caphethuong.jpg',
      price: 0,
      description: 'COMING_SOON',
      taste: '',
      suitable: '',
    ),
    Coffee(
      id: 'c8',
      name: 'Nước ép dứa',
      image: 'images/nuocdua.jpg',
      price: 0,
      description: 'COMING_SOON',
      taste: '',
      suitable: '',
    ),
    Coffee(
      id: 'c9',
      name: 'Sinh Tố Bơ',
      image: 'images/bo.jpg',
      price: 0,
      description: 'COMING_SOON',
      taste: '',
      suitable: '',
    ),
    Coffee(
      id: 'c10',
      name: 'Trà Chanh',
      image: 'images/chanh.jpg',
      price: 0,
      description: 'COMING_SOON',
      taste: '',
      suitable: '',
    ),
  ];

  bool _isLoading = true;
  String? _error;

  List<Coffee> get coffees => _coffees;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchCoffees() async {
    _isLoading = true;
    notifyListeners();
    try {
      // Giả lập thời gian tải
      await Future.delayed(const Duration(seconds: 1));
      _isLoading = false;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
    }
    notifyListeners();
  }
}