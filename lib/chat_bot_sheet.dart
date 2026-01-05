// --- lib/voice_bot_sheet.dart ---
import 'package:cafe_robot/api_service.dart';
import 'package:cafe_robot/models/coffee.dart';
import 'package:cafe_robot/providers/cart_provider.dart';
import 'package:cafe_robot/providers/coffee_provider.dart';
import 'package:cafe_robot/screens/cart_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'dart:ui'; // Cần cho ImageFilter (nếu dùng blur)

enum VoiceState { idle, listening, processing, speaking }

class ChatBotSheet extends StatefulWidget {
  final String? initialMessage;

  const ChatBotSheet({super.key, this.initialMessage});

  @override
  State<ChatBotSheet> createState() => _VoiceBotSheetState();
}

class _VoiceBotSheetState extends State<ChatBotSheet> with TickerProviderStateMixin {
  // Services
  final ApiService _apiService = ApiService();
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  // State
  VoiceState _currentState = VoiceState.idle;
  String _userSaid = "";
  late String _aiResponse;

  final List<Map<String, String>> _messagesHistory = [];
  List<dynamic> _pendingActions = [];
  Timer? _silenceTimer;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 1. Setup Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 2. Setup Logic ban đầu
    _aiResponse = widget.initialMessage ?? "Xin chào, mình là An. Bạn muốn dùng món gì ạ?";
    _messagesHistory.add({"role": "assistant", "content": _aiResponse});

    // Bắt đầu khởi tạo TTS và STT
    _initSpeechAndTts();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _silenceTimer?.cancel();
    _speechToText.stop();
    _flutterTts.stop();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initSpeechAndTts() async {
    try {
      await _speechToText.initialize(onError: (e) => print("Lỗi STT: $e"));
      await _flutterTts.setLanguage("vi-VN");
      await _flutterTts.setPitch(1.0);

      _flutterTts.setCompletionHandler(() {
        if (!mounted) return;

        // Nếu có hành động đặt hàng -> Xử lý ngay
        if (_pendingActions.isNotEmpty) {
          _handleOrder(_pendingActions);
          _pendingActions.clear();
        }
        // Nếu chỉ là hội thoại bình thường -> Bật mic nghe tiếp
        else if (_currentState == VoiceState.speaking) {
          _startListening();
        }
      });

      // Nói câu chào mở đầu
      _speak(_aiResponse);
    } catch (e) {
      print("Lỗi khởi tạo TTS/STT: $e");
    }
  }

  Future<void> _startListening() async {
    if (!mounted) return;

    // Kiểm tra quyền Micro
    bool available = await _speechToText.initialize();
    if (!available) {
      print("Không có quyền Micro");
      return;
    }

    setState(() {
      _currentState = VoiceState.listening;
      _userSaid = "Đang nghe...";
    });

    try {
      _pulseController.repeat(reverse: true);
      _speechToText.listen(
        onResult: (result) {
          _silenceTimer?.cancel();
          setState(() {
            _userSaid = result.recognizedWords;
          });

          _scrollToBottom();

          if (result.finalResult) {
            _silenceTimer?.cancel();
            _stopListeningAndProcess();
          } else {
            // Đợi 1.5s không nói gì thì tự ngắt
            _silenceTimer = Timer(const Duration(milliseconds: 1500), () {
              _stopListeningAndProcess();
            });
          }
        },
        localeId: "vi-VN",
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      );
    } catch (e) {
      print("Lỗi lắng nghe: $e");
    }
  }

  Future<void> _stopListeningAndProcess() async {
    _silenceTimer?.cancel();
    if (mounted) {
      _pulseController.stop();
      _pulseController.reset();
    }

    if (_currentState != VoiceState.listening) return;

    await _speechToText.stop();
    setState(() {
      _currentState = VoiceState.processing;
    });

    // Nếu không nghe thấy gì
    if (_userSaid.isEmpty || _userSaid == "Đang nghe...") {
      _speak("Bạn có thể nói lại không, mình chưa nghe rõ?");
      return;
    }

    // Thêm tin nhắn user vào lịch sử
    _messagesHistory.add({"role": "user", "content": _userSaid});
    _scrollToBottom();

    // Gửi lên Server AI
    try {
      final response = await _apiService.sendMessage(_messagesHistory);

      _aiResponse = response['response_speech'] ?? "Tôi không nghe rõ, xin lỗi bạn.";
      _pendingActions = response['actions'] as List<dynamic>? ?? [];
      final bool endConversation = response['end_conversation'] == true;

      _messagesHistory.add({"role": "assistant", "content": _aiResponse});
      _scrollToBottom();

      // AI trả lời
      _speak(_aiResponse);

      // Nếu AI bảo kết thúc -> Đóng Sheet
      if (endConversation) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) Navigator.pop(context);
        });
      }
    } catch (e) {
      _speak("Có lỗi kết nối, bạn thử lại nhé.");
    }
  }

  Future<void> _speak(String text) async {
    if (!mounted) return;
    setState(() {
      _currentState = VoiceState.speaking;
      _aiResponse = text;
    });
    if (mounted) _pulseController.repeat(reverse: true);
    await _flutterTts.speak(text);
  }

  void _handleOrder(List<dynamic> actions) {
    if (!mounted) return;
    final cart = Provider.of<CartProvider>(context, listen: false);
    final coffeeProvider = Provider.of<CoffeeProvider>(context, listen: false);

    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đang thêm món vào giỏ hàng...')));

    for (var action in actions) {
      final String itemId = action['item_id'];
      final int quantity = action['quantity'] ?? 1;
      try {
        final coffeeToAdd = coffeeProvider.coffees.firstWhere((c) => c.id == itemId);
        for (int i = 0; i < quantity; i++) {
          cart.addItem(coffeeToAdd);
        }
      } catch (e) {
        print("Lỗi item không tìm thấy: $itemId");
      }
    }

    // Sau khi thêm giỏ hàng -> Đợi 2s rồi chuyển trang
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context); // Đóng Sheet -> Trigger 'whenComplete' ở Home
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CartPage()),
        );
      }
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Color accentColor = (_currentState == VoiceState.listening) ? Colors.redAccent : Colors.brown;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: Stack(
          children: [
            // 1. ẢNH NỀN
            Positioned.fill(
              child: Image.asset(
                "images/uet2.jpg", // Đảm bảo đường dẫn đúng
                fit: BoxFit.cover,
              ),
            ),

            // 2. LỚP PHỦ MỜ
            Positioned.fill(
              child: Container(color: Colors.white.withOpacity(0.85)),
            ),

            // 3. NỘI DUNG CHÍNH
            Column(
              children: [
                const SizedBox(height: 15),
                // Thanh kéo nhỏ
                Container(
                  width: 50, height: 5,
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10)),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.brown.shade800,
                        child: const Icon(Icons.support_agent, color: Colors.white),
                      ),
                      const SizedBox(width: 15),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Trợ lý ảo An", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text("Sẵn sàng hỗ trợ bạn", style: TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                      const Spacer(),
                      // Nút đóng thủ công
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Khu vực Chat
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(15),
                    itemCount: _messagesHistory.length + (_currentState == VoiceState.listening ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Hiển thị tin nhắn đang nói (Preview)
                      if (index == _messagesHistory.length) {
                        return _buildChatBubble("user", _userSaid, true);
                      }
                      final msg = _messagesHistory[index];
                      return _buildChatBubble(msg['role']!, msg['content']!, false);
                    },
                  ),
                ),

                // Khu vực Điều khiển (Mic)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _currentState == VoiceState.listening ? "Đang nghe..." : "Chạm để nói",
                        style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 15),
                      GestureDetector(
                        onTap: () {
                          if (_currentState == VoiceState.listening) {
                            _stopListeningAndProcess();
                          } else {
                            _startListening();
                          }
                        },
                        child: ScaleTransition(
                          scale: _pulseAnimation,
                          child: Container(
                            width: 70, height: 70,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: accentColor.withOpacity(0.4), blurRadius: 15, spreadRadius: 2)],
                            ),
                            child: Icon(
                              _currentState == VoiceState.listening ? Icons.mic : Icons.mic_none,
                              color: Colors.white, size: 35,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(String role, String content, bool isPreview) {
    bool isBot = role == "assistant";
    return Align(
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isPreview ? Colors.grey.shade200 : (isBot ? Colors.white : Colors.brown.shade700),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isBot ? 4 : 20),
            bottomRight: Radius.circular(isBot ? 20 : 4),
          ),
          boxShadow: [
            if (!isPreview) BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(1, 2))
          ],
          border: isBot ? Border.all(color: Colors.grey.shade300) : null,
        ),
        child: Text(
          content,
          style: TextStyle(
            color: isPreview ? Colors.black54 : (isBot ? Colors.black87 : Colors.white),
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}