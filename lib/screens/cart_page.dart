// --- lib/screens/cart_page.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:cafe_robot/providers/cart_provider.dart';
import 'package:cafe_robot/screens/checkout_page.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final _voucherController = TextEditingController();
  String? _voucherMessage; // Để hiển thị thông báo
  bool _isError = false; // Để đổi màu thông báo

  @override
  void dispose() {
    _voucherController.dispose();
    super.dispose();
  }

  // Hàm xử lý khi nhấn "Áp dụng"
  void _applyVoucher() {
    final cart = Provider.of<CartProvider>(context, listen: false);
    final code = _voucherController.text;
    if (code.isEmpty) return;

    final message = cart.applyVoucher(code);

    setState(() {
      _voucherMessage = message;
      // Kiểm tra xem có thành công không
      _isError = !message.contains("thành công");
      _voucherController.clear();
    });

    // Ẩn bàn phím
    FocusScope.of(context).unfocus();
  }

  // Hàm xử lý khi nhấn "Xóa" voucher
  void _removeVoucher() {
    final cart = Provider.of<CartProvider>(context, listen: false);
    cart.removeVoucher();
    setState(() {
      _voucherMessage = "Đã xóa voucher.";
      _isError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Dùng Consumer ở đây để toàn bộ trang build lại khi cart thay đổi
    return Consumer<CartProvider>(
      builder: (context, cart, child) {
        // Đặt formatter ở đây để ListView cũng dùng được
        final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: 'vnđ');

        return Scaffold(
          appBar: AppBar(
            title: const Text('Giỏ hàng của bạn'),
          ),
          body: Column(
            children: [
              // --- PHẦN BỊ LỖI LÀ Ở ĐÂY ---
              Expanded(
                child: cart.items.isEmpty
                    ? const Center(
                  child: Text(
                    'Giỏ hàng của bạn đang trống.',
                    style: TextStyle(fontSize: 18),
                  ),
                )
                    : ListView.builder(
                  itemCount: cart.items.length,
                  // --- ĐÂY LÀ PHẦN CODE BỊ THIẾU ---
                  itemBuilder: (ctx, index) {
                    final item = cart.items[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: AssetImage(item.image),
                      ),
                      title: Text(item.name),
                      subtitle: Text(formatter.format(item.price)),
                      trailing: const Text('x1'), // (Phiên bản đơn giản)
                    );
                  },
                  // --- KẾT THÚC PHẦN BỊ THIẾU ---
                ),
              ),

              // --- PHẦN THANH TOÁN ---
              if (cart.items.isNotEmpty)
                _buildPaymentSection(cart, formatter),
            ],
          ),
        );
      },
    );
  }

  // --- WIDGET: Toàn bộ khu vực thanh toán ---
  Widget _buildPaymentSection(CartProvider cart, NumberFormat formatter) {
    return Card(
      margin: const EdgeInsets.all(15),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            // 1. Ô nhập Voucher
            _buildVoucherInput(cart),

            // 2. Thông báo (nếu có)
            if (_voucherMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Text(
                  _voucherMessage!,
                  style: TextStyle(
                    color: _isError ? Colors.red : Colors.green,
                  ),
                ),
              ),

            const Divider(height: 20),

            // 3. Chi tiết giá
            _buildPriceRow(
              'Tạm tính:',
              formatter.format(cart.subtotal),
            ),

            // Hiển thị nếu có giảm giá
            if (cart.discountAmount > 0)
              _buildPriceRow(
                'Giảm giá:',
                '- ${formatter.format(cart.discountAmount)}',
                color: Colors.green,
              ),

            const SizedBox(height: 10),

            // 4. Tổng cộng
            _buildPriceRow(
              'Tổng cộng:',
              formatter.format(cart.totalAmount),
              isTotal: true,
            ),

            const SizedBox(height: 15),

            // 5. Nút Thanh toán
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CheckoutPage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.brown.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text(
                  'Thanh toán',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- WIDGET: Ô nhập/hiển thị voucher ---
  Widget _buildVoucherInput(CartProvider cart) {
    // Nếu chưa áp dụng voucher
    if (cart.appliedVoucherCode == null) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _voucherController,
              decoration: const InputDecoration(
                labelText: 'Nhập mã voucher',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _applyVoucher(),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _applyVoucher,
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)
            ),
            child: const Text('Áp dụng'),
          ),
        ],
      );
    }

    // Nếu đã áp dụng voucher
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Đã áp dụng mã:',
              style: TextStyle(color: Colors.black54),
            ),
            Text(
              cart.appliedVoucherCode!,
              style: TextStyle(
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        TextButton.icon(
          icon: const Icon(Icons.clear, size: 18),
          label: const Text('Xóa'),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: _removeVoucher,
        ),
      ],
    );
  }

  // --- WIDGET: Hiển thị 1 hàng giá ---
  Widget _buildPriceRow(String title, String amount,
      {Color? color, bool isTotal = false}) {
    final style = TextStyle(
      fontSize: isTotal ? 20 : 16,
      fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
      color: color ?? Colors.black,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: style.copyWith(fontWeight: FontWeight.normal, fontSize: 16)),
          Text(amount, style: style),
        ],
      ),
    );
  }
}