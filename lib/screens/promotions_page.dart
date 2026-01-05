// --- lib/screens/promotions_page.dart ---
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PromotionsPage extends StatelessWidget {
  const PromotionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const String voucherCode = "UET_ENDYEAR";
    const String promoImage = 'images/sale.jpg';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(15.0),
      child: Center(
        child: Column(
          children: [
            // 1. Hiển thị ảnh ưu đãi
            Card(
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                promoImage,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 20),

            // 2. Hiển thị mã voucher
            Card(
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(25.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.card_giftcard,
                      size: 50,
                      color: Colors.brown.shade700,
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'Ưu đãi Cuối Năm!',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Giảm 100% cho toàn bộ đơn hàng.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Nhập mã:',
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                    ),
                    Text(
                      voucherCode,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.brown.shade800,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 25),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Sao chép mã'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.brown,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30, vertical: 12),
                      ),
                      onPressed: () {
                        Clipboard.setData(
                            const ClipboardData(text: voucherCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đã sao chép mã!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}