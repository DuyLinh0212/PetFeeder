import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import 'safety_settings.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback onRefresh;
  const SettingsScreen({super.key, required this.onRefresh});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<AlertNotification> _alerts = [];
  bool _loading = true;
  bool _failed = false;
  bool _testing = false;
  bool _clearing = false;
  String? _connectionMessage;
  bool _connectionOk = false;

  @override
  void initState() {
    super.initState();
    _url.text = ApiService().baseUrl;
    _loadAlerts();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _loadAlerts() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final alerts = await ApiService().getNotifications();
      if (mounted) setState(() => _alerts = alerts);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    if (_testing || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _connectionMessage = null;
    });
    final candidate = _url.text.trim().replaceFirst(RegExp(r'/+$'), '');
    try {
      final status = await ApiService().getDeviceStatus(serverUrl: candidate);
      if (!mounted) return;
      await ApiService().setBaseUrl(candidate);
      if (!mounted) return;
      setState(() {
        _connectionOk = true;
        _connectionMessage = status.online
            ? 'Đã kết nối. Thiết bị sẵn sàng chăm bé.'
            : 'Đã kết nối máy chủ. Thiết bị hiện ngoại tuyến.';
      });
      widget.onRefresh();
      await _loadAlerts();
    } catch (_) {
      if (mounted) {
        setState(() {
          _connectionOk = false;
          _connectionMessage =
              'Không kết nối được. Kiểm tra địa chỉ và mạng Wi-Fi rồi thử lại.';
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _clearAlerts() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    try {
      if (!await ApiService().clearNotifications()) throw Exception('clear');
      if (mounted) setState(() => _alerts = []);
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Chưa xóa được cảnh báo. Hãy thử lại.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Widget _alert(AlertNotification a) {
    final color = a.level == 'error'
        ? AppTheme.accentCoral
        : a.level == 'warning'
        ? AppTheme.accentAmber
        : AppTheme.accentGreen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              a.level == 'error'
                  ? Icons.error_outline_rounded
                  : a.level == 'warning'
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline_rounded,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    a.message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                      height: 1.5,
                    ),
                  ),
                  if (!a.read) ...[
                    const SizedBox(height: 8),
                    StatusPill(label: 'Mới', color: color),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageContent(
    child: RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView(
        padding: AppTheme.pagePadding,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const PageHeading(
            title: 'Kết nối & cài đặt',
            subtitle: 'Thiết lập máy chủ và theo dõi cảnh báo.',
          ),
          SectionCard(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.wifi_rounded,
                          color: AppTheme.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Kết nối thiết bị',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Nhập địa chỉ máy chủ PetFeeder. Điện thoại và máy chủ cần truy cập được cùng mạng.',
                    style: TextStyle(color: AppTheme.textMuted, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _url,
                    enabled: !_testing,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _connect(),
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ máy chủ',
                      hintText: 'http://192.168.1.15:3000',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                    validator: (value) {
                      final uri = Uri.tryParse(value?.trim() ?? '');
                      if (uri == null ||
                          !['http', 'https'].contains(uri.scheme) ||
                          uri.host.isEmpty ||
                          uri.hasQuery ||
                          uri.hasFragment ||
                          uri.userInfo.isNotEmpty) {
                        return 'Nhập địa chỉ http:// hoặc https:// hợp lệ.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _testing ? null : _connect,
                      icon: _testing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find_rounded),
                      label: Text(_testing ? 'Đang kết nối…' : 'Lưu kết nối'),
                    ),
                  ),
                  if (_connectionMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _connectionMessage!,
                      style: TextStyle(
                        color: _connectionOk
                            ? AppTheme.accentGreen
                            : AppTheme.accentCoral,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    title: const Text(
                      'Tùy chọn phát triển',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('Máy tính này'),
                            onPressed: _testing
                                ? null
                                : () => _url.text = 'http://localhost:3000',
                          ),
                          ActionChip(
                            label: const Text('Giả lập Android'),
                            onPressed: _testing
                                ? null
                                : () => _url.text = 'http://10.0.2.2:3000',
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          SafetySettings(
            key: ValueKey(ApiService().baseUrl),
            onSaved: widget.onRefresh,
          ),
          const SizedBox(height: 28),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Thông báo & cảnh báo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              if (_alerts.isNotEmpty && !_failed)
                TextButton(
                  onPressed: _clearing ? null : _clearAlerts,
                  child: Text(_clearing ? 'Đang xóa…' : 'Xóa tất cả'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed)
            EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Chưa tải được thông báo',
              message: 'Kiểm tra kết nối rồi thử lại.',
              action: OutlinedButton(
                onPressed: _loadAlerts,
                child: const Text('Thử lại'),
              ),
            )
          else if (_alerts.isEmpty)
            const EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'Chưa có cảnh báo',
              message:
                  'Bạn sẽ thấy thông báo ở đây khi thiết bị cần được chú ý.',
            )
          else
            ..._alerts.map(_alert),
          const SizedBox(height: 20),
          const Card(
            child: ExpansionTile(
              tilePadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              childrenPadding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              leading: Icon(
                Icons.info_outline_rounded,
                color: AppTheme.primary,
              ),
              title: Text('Về PetFeeder'),
              children: [
                Text(
                  'Hệ thống cho thú cưng ăn tự động\n\nESP32 · Servo cấp hạt và chống kẹt\nHC-SR04 · Cảm biến mức hạt\nHX711 + Load Cell · Cân thức ăn\nMQTT & REST API · Kết nối thiết bị',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
