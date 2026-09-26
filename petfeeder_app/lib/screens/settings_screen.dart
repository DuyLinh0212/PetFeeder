import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onRefresh;

  const SettingsScreen({super.key, required this.onRefresh});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  List<AlertNotification> _alerts = [];
  bool _isLoadingAlerts = true;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = ApiService().baseUrl;
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoadingAlerts = true);
    try {
      final list = await ApiService().getNotifications();
      setState(() => _alerts = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingAlerts = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    try {
      ApiService().setBaseUrl(_urlController.text.trim());
      final status = await ApiService().getDeviceStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.accentGreen,
          content: Text('Kết nối Backend thành công! ESP32: ${status.online ? "Trực tuyến" : "Ngoại tuyến"}'),
        ),
      );
      widget.onRefresh();
      _loadAlerts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.accentCoral,
          content: Text('Không thể kết nối Backend tại URL này: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt & Cảnh báo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API Server Configuration Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.dns_rounded, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text(
                          'Cấu hình địa chỉ Backend',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: 'REST API Base URL',
                        hintText: 'http://localhost:3000 hoặc http://10.0.2.2:3000',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        prefixIcon: const Icon(Icons.link_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Localhost (3000)'),
                          onPressed: () => setState(() => _urlController.text = 'http://localhost:3000'),
                        ),
                        ActionChip(
                          label: const Text('Android Emulator (10.0.2.2)'),
                          onPressed: () => setState(() => _urlController.text = 'http://10.0.2.2:3000'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isTesting ? null : _testConnection,
                        icon: _isTesting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.wifi_find_rounded),
                        label: const Text('LƯU & KIỂM TRA KẾT NỐI'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Alert Notifications Center (FR-07)
            Row(
              children: [
                const Icon(Icons.notifications_active_rounded, color: AppTheme.accentCoral),
                const SizedBox(width: 8),
                const Text(
                  'Cảnh báo hệ thống',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_alerts.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await ApiService().clearNotifications();
                      _loadAlerts();
                    },
                    child: const Text('Xóa tất cả', style: TextStyle(color: AppTheme.textMuted)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _isLoadingAlerts
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                : _alerts.isEmpty
                    ? Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: const Center(
                          child: Text('Không có cảnh báo mới nào.', style: TextStyle(color: AppTheme.textMuted)),
                        ),
                      )
                    : Column(
                        children: _alerts.map((a) {
                          Color color = AppTheme.accentGreen;
                          IconData icon = Icons.info_outline;
                          if (a.level == 'error') {
                            color = AppTheme.accentCoral;
                            icon = Icons.error_outline;
                          } else if (a.level == 'warning') {
                            color = AppTheme.accentAmber;
                            icon = Icons.warning_amber_rounded;
                          }

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              child: ListTile(
                                leading: Icon(icon, color: color, size: 28),
                                title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                subtitle: Text(a.message, style: const TextStyle(fontSize: 12)),
                                trailing: a.read
                                    ? null
                                    : Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: AppTheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
            const SizedBox(height: 24),

            // Hardware & Project Specs (BaoCaoGiaiDoan2.docx)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Thông tin đề tài IoT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    _buildInfoRow('Hệ thống:', 'Hệ thống cho thú cưng ăn tự động'),
                    _buildInfoRow('Vi điều khiển:', 'ESP32 DevKit V1 (240 MHz)'),
                    _buildInfoRow('Cơ cấu cấp thức ăn:', 'Servo SG90 / MG996R (Closed-loop)'),
                    _buildInfoRow('Cơ cấu chống kẹt:', 'Anti-Jam Oscillating Servo'),
                    _buildInfoRow('Cảm biến bồn chứa:', 'Cảm biến siêu âm HC-SR04'),
                    _buildInfoRow('Cảm biến cân bát:', 'HX711 24-bit ADC + Load Cell'),
                    _buildInfoRow('Giao thức truyền thông:', 'MQTT (Mosquitto Broker) & REST API'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
