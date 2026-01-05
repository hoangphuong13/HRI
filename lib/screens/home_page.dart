// --- lib/screens/home_page.dart ---
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';

import 'package:cafe_robot/providers/cart_provider.dart';
import 'package:cafe_robot/screens/cart_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:cafe_robot/screens/store_page.dart';
import 'package:cafe_robot/screens/promotions_page.dart';
import 'package:cafe_robot/screens/manual_control_page.dart';

import 'package:cafe_robot/chat_bot_sheet.dart';
import 'package:cafe_robot/voice_bot_sheet.dart';

class CoffeeHomePage extends StatefulWidget {
  const CoffeeHomePage({super.key});

  @override
  State<CoffeeHomePage> createState() => _CoffeeHomePageState();
}

class _CoffeeHomePageState extends State<CoffeeHomePage> {
  int _selectedIndex = 0;

  // --- CẤU HÌNH SERVER ---
  // Hãy đảm bảo IP này đúng với máy chạy server.py
  final String serverUrl = "http://192.168.1.136:5000";
  Timer? _pollingTimer;
  bool _isVoiceBotOpen = false;
  final FlutterTts flutterTts = FlutterTts();

  static const List<Widget> _pages = <Widget>[
    StorePage(),
    PromotionsPage(),
    ManualControlPage(),
  ];

  static const List<String> _pageTitles = <String>[
    'Coffee UET',
    'Ưu đãi & Khuyến mãi',
    'Điều khiển Robot 6DOF',
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("vi-VN");
    await flutterTts.setPitch(1.0);
  }

  // --- LOGIC POLLING (Check Server liên tục) ---
  void _startPolling() {
    // Check mỗi 2 giây
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      await _checkServerStatus();
    });
  }

  Future<void> _checkServerStatus() async {
    try {
      // 1. KIỂM TRA KHÁCH ĐẾN
      // Chỉ check khi Bot đang ĐÓNG (để tránh mở 2 lần)
      if (!_isVoiceBotOpen) {
        final resArrival = await http.get(Uri.parse('$serverUrl/check-arrival'));
        if (resArrival.statusCode == 200) {
          final data = jsonDecode(resArrival.body);
          if (data['arrived'] == true) {
            print("FLUTTER: Khách đến! Mở Bot.");
            _openVoiceBot(autoGreeting: data['message']);
          }
        }
      }

      // 2. KIỂM TRA KHÁCH ĐI
      // Luôn check để kịp thời nói tạm biệt
      final resDeparture = await http.get(Uri.parse('$serverUrl/check-departure'));
      if (resDeparture.statusCode == 200) {
        final data = jsonDecode(resDeparture.body);
        if (data['left'] == true) {
          print("FLUTTER: Khách đi! Tạm biệt.");

          // A. Nói lời tạm biệt
          await flutterTts.speak(data['message'] ?? "Tạm biệt quý khách!");

          // B. Nếu Bot đang mở (mà khách đã đi mất) -> Đóng lại
          if (_isVoiceBotOpen && mounted) {
            Navigator.of(context).pop();
            setState(() {
              _isVoiceBotOpen = false;
            });
          }
        }
      }
    } catch (e) {
      print("Lỗi kết nối Server: $e");
    }
  }

  // --- HÀM MỞ BOT QUAN TRỌNG ---
  void _openVoiceBot({String? autoGreeting}) {
    if (_isVoiceBotOpen) return;

    setState(() {
      _isVoiceBotOpen = true;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false, // [QUAN TRỌNG] Chặn vuốt xuống để bắt buộc dùng logic đóng chuẩn
      builder: (_) => VoiceBotSheet(initialMessage: autoGreeting),
    ).whenComplete(() {
      // Khi Sheet đóng lại (dù bằng cách nào: nút X, code tự đóng...)
      setState(() {
        _isVoiceBotOpen = false;
      });
      print("Bot đã đóng.");

      // [QUAN TRỌNG] Báo cho Server biết phiên phục vụ đã xong
      // Server sẽ chuyển trạng thái sang "LEAVING" để Camera bắt đầu canh khách đi
      _notifySessionComplete();
    });
  }

  // Gửi tín hiệu hoàn tất phiên
  Future<void> _notifySessionComplete() async {
    try {
      await http.post(Uri.parse('$serverUrl/session-complete'));
      print(" Đã gửi tín hiệu SESSION COMPLETE -> Chờ khách đi.");
    } catch (e) {
      print("Lỗi gửi session complete: $e");
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _pageTitles[_selectedIndex],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.storefront_outlined),
            activeIcon: Icon(Icons.storefront),
            label: 'Cửa hàng',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.card_giftcard_outlined),
            activeIcon: Icon(Icons.card_giftcard),
            label: 'Ưu đãi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.smart_toy_outlined),
            activeIcon: Icon(Icons.smart_toy),
            label: 'Điều khiển',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.brown.shade700,
        unselectedItemColor: Colors.grey.shade600,
        onTap: _onItemTapped,
        showUnselectedLabels: true,
      ),
      floatingActionButton: _selectedIndex == 0
          ? Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartPage()),
              );
            },
            backgroundColor: Colors.white,
            foregroundColor: Colors.brown.shade700,
            heroTag: 'cart_button',
            label: const Text('Giỏ hàng'),
            icon: Consumer<CartProvider>(
              builder: (context, cart, child) => Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.shopping_cart_outlined),
                  if (cart.items.isNotEmpty)
                    Positioned(
                      right: -8,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                            minWidth: 16, minHeight: 16),
                        child: Text(
                          '${cart.items.length}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            onPressed: () {
              _showModeSelectionSheet(context);
            },
            label: const Text('Chat với An'),
            icon: const Icon(Icons.support_agent),
            backgroundColor: Colors.brown.shade700,
            foregroundColor: Colors.white,
            heroTag: 'chat_button',
          ),
        ],
      )
          : null,
    );
  }

  void _showModeSelectionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bạn muốn làm gì?',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Icon(Icons.gamepad_outlined, color: Colors.blue.shade700),
                title: const Text('Điều khiển tay (Manual)'),
                subtitle: const Text('Gửi góc trực tiếp cho robot'),
                onTap: () {
                  Navigator.pop(ctx);
                  _onItemTapped(2);
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.chat_bubble_outline, color: Colors.brown.shade700),
                title: const Text('Chat (Gõ chữ)'),
                subtitle: const Text('Trò chuyện với An bằng tin nhắn'),
                onTap: () {
                  Navigator.pop(ctx);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => const ChatBotSheet(),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.mic_none_outlined, color: Colors.brown.shade700),
                title: const Text('Nói chuyện (Giọng nói)'),
                subtitle: const Text('Trò chuyện rảnh tay với An'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openVoiceBot(); // Mở thủ công
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}