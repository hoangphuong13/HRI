// --- lib/screens/manual_control_page.dart ---
import 'package:cafe_robot/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Cho ô nhập số

class ManualControlPage extends StatefulWidget {
  const ManualControlPage({super.key});

  @override
  State<ManualControlPage> createState() => _ManualControlPageState();
}

class _ManualControlPageState extends State<ManualControlPage> {
  final ApiService _apiService = ApiService();
  bool _isLoadingFK = false; // Loading cho Gửi Góc (FK)
  bool _isLoadingIK = false; // Loading cho Gửi Tọa độ (IK)

  // Controller cho 3 ô X, Y, Z
  final _xController = TextEditingController(text: "0");
  final _yController = TextEditingController(text: "0");
  final _zController = TextEditingController(text: "0");

  // === Trạng thái Robot ===
  final List<String> _jointNames = ["q1 (Trụ)", "q2 (Vai)", "q3 (Cùi)", "q4 (Cổ tay 1)", "q5 (Cổ tay 2)", "q6 (Vặn)"];
  final List<Map<String, double>> _jointLimits = [
    {"min": -180, "max": 180}, {"min": -90, "max": 90}, {"min": -90, "max": 90},
    {"min": -180, "max": 180}, {"min": -90, "max": 90}, {"min": -180, "max": 180},
  ];

  // Mảng 6 góc (trạng thái hiện tại)
  List<double> _allAngles = List<double>.filled(6, 0.0);
  int _selectedJoint = 0; // Khớp (q1-q6) đang được chọn

  // --- MỚI: Controller cho ô nhập góc ---
  late TextEditingController _angleInputController;
  // ------------------------------------

  @override
  void initState() {
    super.initState();
    _angleInputController = TextEditingController(text: "0.0");
  }

  @override
  void dispose() {
    _xController.dispose();
    _yController.dispose();
    _zController.dispose();
    _angleInputController.dispose(); // Hủy controller mới
    super.dispose();
  }

  // --- HÀM GỌI API ---

  // Gửi 6 góc (FK)
  Future<void> _sendFKAngles() async {
    // Cập nhật góc cuối cùng từ ô text (phòng trường hợp người dùng gõ mà chưa submit)
    _updateAngleFromText();

    setState(() { _isLoadingFK = true; });
    final bool success = await _apiService.sendManualAngles(_allAngles);
    if (mounted) {
      _showSnackBar(success, success ? 'Đã gửi lệnh góc!' : 'Lỗi: Robot không phản hồi!');
      setState(() { _isLoadingFK = false; });
    }
  }

  // Gửi tọa độ X,Y,Z (IK)
  Future<void> _sendIKCoords() async {
    setState(() { _isLoadingIK = true; });
    final double x = double.tryParse(_xController.text) ?? 0;
    final double y = double.tryParse(_yController.text) ?? 0;
    final double z = double.tryParse(_zController.text) ?? 0;

    final List<double>? calculatedAngles = await _apiService.sendInverseKinematics(x, y, z);

    if (mounted) {
      if (calculatedAngles != null) {
        _showSnackBar(true, 'Robot đã nhận lệnh IK!');
        // CẬP NHẬT TRẠNG THÁI:
        setState(() {
          _allAngles = calculatedAngles;
          // Cập nhật ô text cho khớp đang chọn
          _angleInputController.text = _allAngles[_selectedJoint].toStringAsFixed(1);
        });
      } else {
        _showSnackBar(false, 'Lỗi: Không thể tính toán hoặc gửi lệnh IK.');
      }
      setState(() { _isLoadingIK = false; });
    }
  }

  // Hiển thị thông báo
  void _showSnackBar(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  // --- HÀM MỚI: Cập nhật góc (từ +/- hoặc Text) ---
  void _updateAngle(double newAngle) {
    // Lấy giới hạn
    final limits = _jointLimits[_selectedJoint];
    final double min = limits['min']!;
    final double max = limits['max']!;

    // Kẹp giá trị trong giới hạn
    newAngle = newAngle.clamp(min, max);

    // Cập nhật
    setState(() {
      _allAngles[_selectedJoint] = (newAngle * 10).round() / 10; // Làm tròn 1 chữ số
      _angleInputController.text = _allAngles[_selectedJoint].toStringAsFixed(1);
    });
  }

  // Đọc giá trị từ ô text
  void _updateAngleFromText() {
    double angle = double.tryParse(_angleInputController.text) ?? 0.0;
    _updateAngle(angle);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0).copyWith(bottom: 80),
        children: [
          _buildIKPanel(), // Bảng Động học ngược (X,Y,Z)
          const SizedBox(height: 20),
          _buildFKPanel(), // Bảng Động học thuận (q1-q6)
          const SizedBox(height: 20),
          _buildStatusTable(), // Bảng Trạng thái góc
        ],
      ),
    );
  }

  // --- CÁC WIDGET CON ---

  // Bảng Trạng thái (yêu cầu của bạn)
  Widget _buildStatusTable() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Trạng thái góc hiện tại", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Table(
              border: TableBorder.all(color: Colors.grey.shade300, width: 1),
              children: List.generate(6, (index) {
                return TableRow(
                  decoration: BoxDecoration(
                    color: (index == _selectedJoint) ? Colors.brown.withOpacity(0.1) : Colors.transparent,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Text(
                          _jointNames[index],
                          style: const TextStyle(fontWeight: FontWeight.bold)
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Text(
                          '${_allAngles[index].toStringAsFixed(1)}°',
                          style: const TextStyle(fontSize: 16)
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // Bảng Động học thuận (ĐÃ THAY THẾ SLIDER)
  Widget _buildFKPanel() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Điều khiển góc (FK)", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 15),

            // 1. Bộ chọn khớp (q1-q6)
            ToggleButtons(
              isSelected: List.generate(6, (i) => i == _selectedJoint),
              onPressed: (int index) {
                setState(() {
                  _selectedJoint = index;
                  // Cập nhật ô text khi đổi khớp
                  _angleInputController.text = _allAngles[_selectedJoint].toStringAsFixed(1);
                });
              },
              borderRadius: BorderRadius.circular(8.0),
              selectedColor: Colors.white,
              selectedBorderColor: Colors.brown,
              fillColor: Colors.brown.shade600,
              children: _jointNames.map((name) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: Text(name.split(" ")[0]), // Chỉ lấy "q1"
              )).toList(),
            ),
            const SizedBox(height: 20),

            // 2. Tên khớp đang chọn
            Text(
              'Đang chỉnh: ${_jointNames[_selectedJoint]}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),

            // 3. --- BỘ ĐIỀU KHIỂN MỚI (+/- VÀ Ô NHẬP) ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Nút Trừ
                IconButton.filled(
                  icon: const Icon(Icons.remove),
                  onPressed: (_isLoadingFK || _isLoadingIK) ? null : () {
                    _updateAngle(_allAngles[_selectedJoint] - 1.0); // Trừ 1 độ
                  },
                  iconSize: 28,
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.red.shade400,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                ),

                // Ô Nhập
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0),
                    child: TextField(
                      controller: _angleInputController,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: "Góc (°)",
                        border: OutlineInputBorder(),
                        suffixText: "°",
                      ),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
                      ],
                      onSubmitted: (value) {
                        _updateAngleFromText(); // Cập nhật khi nhấn Enter
                      },
                      onTapOutside: (e) {
                        _updateAngleFromText(); // Cập nhật khi bấm ra ngoài
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                ),

                // Nút Cộng
                IconButton.filled(
                  icon: const Icon(Icons.add),
                  onPressed: (_isLoadingFK || _isLoadingIK) ? null : () {
                    _updateAngle(_allAngles[_selectedJoint] + 1.0); // Cộng 1 độ
                  },
                  iconSize: 28,
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                ),
              ],
            ),
            // --- KẾT THÚC BỘ ĐIỀU KHIỂN MỚI ---

            const SizedBox(height: 20),

            // 4. Nút Gửi (FK)
            ElevatedButton.icon(
              onPressed: (_isLoadingFK || _isLoadingIK) ? null : _sendFKAngles,
              icon: _isLoadingFK
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: const Text('Gửi 6 Góc (FK)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.brown.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Bảng Động học ngược (X,Y,Z) - (Giữ nguyên)
  Widget _buildIKPanel() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text("Điều khiển tọa độ (IK)", style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 15),
            Row(
              children: [
                _buildXYZInput("X", _xController),
                const SizedBox(width: 10),
                _buildXYZInput("Y", _yController),
                const SizedBox(width: 10),
                _buildXYZInput("Z", _zController),
              ],
            ),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              onPressed: (_isLoadingFK || _isLoadingIK) ? null : _sendIKCoords,
              icon: _isLoadingIK
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.calculate),
              label: const Text('Tính toán & Gửi (IK)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget con cho ô nhập X,Y,Z (Giữ nguyên)
  Widget _buildXYZInput(String label, TextEditingController controller) {
    return Expanded(
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixText: "$label: ",
        ),
        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
        ],
      ),
    );
  }
}