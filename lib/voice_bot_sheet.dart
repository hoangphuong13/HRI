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
import 'dart:ui'; // [NEW] Cần cho ImageFilter nếu muốn blur thật

enum VoiceState { idle, listening, processing, speaking }

class VoiceBotSheet extends StatefulWidget {
  final String? initialMessage;

  const VoiceBotSheet({super.key, this.initialMessage});

  @override
  State<VoiceBotSheet> createState() => _VoiceBotSheetState();
}

class _VoiceBotSheetState extends State<VoiceBotSheet>
    with TickerProviderStateMixin {

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

  // Animation Controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // Setup Animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Setup Logic
    _aiResponse = widget.initialMessage ??
        "Chào bạn, mình là Phương. Bạn muốn đặt món gì ạ?";
    _messagesHistory.add({"role": "assistant", "content": _aiResponse});
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

  // --- LOGIC GIỮ NGUYÊN ---
  Future<void> _initSpeechAndTts() async {
    await _speechToText.initialize(onError: (e) => print("Lỗi STT: $e"));
    await _flutterTts.setLanguage("vi-VN");
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      if (!mounted) return;
      if (_pendingActions.isNotEmpty) {
        _handleOrder(_pendingActions);
        _pendingActions.clear();
      } else if (_currentState == VoiceState.speaking) {
        _startListening();
      }
    });

    _speak(_aiResponse);
  }

  Future<void> _startListening() async {
    if (!mounted) return;
    if (!await _speechToText.initialize()) return;

    setState(() {
      _currentState = VoiceState.listening;
      _userSaid = "Đang nghe...";
    });
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
          _silenceTimer = Timer(const Duration(milliseconds: 1500), () {
            _stopListeningAndProcess();
          });
        }
      },
      localeId: "vi-VN",
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> _stopListeningAndProcess() async {
    _silenceTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    if (_currentState != VoiceState.listening) return;

    _speechToText.stop();
    setState(() {
      _currentState = VoiceState.processing;
    });

    if (_userSaid.isEmpty || _userSaid == "Đang nghe...") {
      _speak("Bạn có thể nói lại không, mình chưa nghe rõ?");
      return;
    }

    _messagesHistory.add({"role": "user", "content": _userSaid});
    _scrollToBottom();

    final response = await _apiService.sendMessage(_messagesHistory);

    _aiResponse = response['response_speech'] ?? "Tôi không nghe rõ";
    _pendingActions = response['actions'] as List<dynamic>? ?? [];
    final bool endConversation = response['end_conversation'] == true;

    _messagesHistory.add({"role": "assistant", "content": _aiResponse});
    _scrollToBottom();
    _speak(_aiResponse);

    if (endConversation) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _speak(String text) async {
    if (!mounted) return;
    setState(() {
      _currentState = VoiceState.speaking;
      _aiResponse = text;
    });
    _pulseController.repeat(reverse: true);
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
        final coffeeToAdd =
        coffeeProvider.coffees.firstWhere((c) => c.id == itemId);
        for (int i = 0; i < quantity; i++) {
          cart.addItem(coffeeToAdd);
        }
      } catch (e) {
        print("Lỗi item: $itemId");
      }
    }

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
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

  // --- GIAO DIỆN (UI) CÓ ẢNH NỀN ---
  @override
  Widget build(BuildContext context) {
    Color accentColor;
    String statusText;
    switch (_currentState) {
      case VoiceState.listening:
        accentColor = Colors.redAccent;
        statusText = "Đang nghe bạn nói...";
        break;
      case VoiceState.processing:
        accentColor = Colors.amber;
        statusText = "Đang suy nghĩ...";
        break;
      case VoiceState.speaking:
        accentColor = Colors.greenAccent;
        statusText = "Phương đang trả lời...";
        break;
      default:
        accentColor = Colors.grey;
        statusText = "Chạm để nói";
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      // Decoration cho cái khung ngoài cùng
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)
        ],
      ),
      // [QUAN TRỌNG] ClipRRect để cắt ảnh theo góc bo tròn của Sheet
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                "images/uet2.jpg", // <-- Đảm bảo đường dẫn và tên file chính xác
                fit: BoxFit.cover, // Giúp ảnh tràn khung hình mà không bị méo
              ),
            ),

            // 2. LỚP PHỦ MỜ (OVERLAY) - Giúp chữ dễ đọc
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  // Màu trắng mờ 85%
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
            ),

            // 3. NỘI DUNG CHÍNH (COLUMN CŨ)
            Column(
              children: [
                // Thanh kéo
                Container(
                  width: 50,
                  height: 5,
                  margin: const EdgeInsets.only(top: 15, bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
                          Text("Trợ lý ảo Phương",
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text("Luôn sẵn sàng hỗ trợ",
                              style: TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                ),
                const Divider(),

                // Chat Area
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(15),
                    itemCount: _messagesHistory.length +
                        (_currentState == VoiceState.listening ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messagesHistory.length) {
                        return _buildChatBubble("user", _userSaid, true);
                      }
                      final msg = _messagesHistory[index];
                      return _buildChatBubble(msg['role']!, msg['content']!, false);
                    },
                  ),
                ),

                // Controls Area
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    // Nền trắng ở dưới cùng để làm nổi bật nút Mic
                    color: Colors.white.withOpacity(0.9),
                    borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, -5))
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        statusText,
                        style: TextStyle(
                            color: accentColor, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
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
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withOpacity(0.4),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                )
                              ],
                            ),
                            child: Icon(
                              _currentState == VoiceState.listening
                                  ? Icons.mic
                                  : (_currentState == VoiceState.processing
                                  ? Icons.hourglass_top
                                  : Icons.mic_none),
                              color: Colors.white,
                              size: 40,
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

  // Widget bong bóng chat
  Widget _buildChatBubble(String role, String content, bool isPreview) {
    bool isBot = role == "assistant" || role == "bot";
    return Align(
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints:
        BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isPreview
              ? Colors.grey.shade200
              : (isBot ? Colors.white : Colors.brown.shade700),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isBot ? 5 : 20),
            bottomRight: Radius.circular(isBot ? 20 : 5),
          ),
          boxShadow: [
            if (!isPreview)
              BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 5,
                  offset: const Offset(2, 2))
          ],
          border: isBot ? Border.all(color: Colors.grey.shade300) : null,
        ),
        child: Text(
          content,
          style: TextStyle(
            color: isPreview
                ? Colors.grey
                : (isBot ? Colors.black87 : Colors.white),
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}