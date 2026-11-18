import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
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
  final _accessKey = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _testing = false;
  String? _connectionMessage;
  bool _connectionOk = false;
  bool _notificationsEnabled = false;
  bool _notificationsBusy = false;
  bool? _pushDeliveryReady;
  String? _notificationMessage;

  @override
  void initState() {
    super.initState();
    _url.text = ApiService().baseUrl;
    _accessKey.text = ApiService().accessKey;
    _loadNotificationState();
  }

  Future<void> _loadNotificationState() async {
    final enabled = await NotificationService.instance.isEnabled();
    if (mounted) setState(() => _notificationsEnabled = enabled);
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    if (_notificationsBusy) return;
    setState(() {
      _notificationsBusy = true;
      _notificationMessage = null;
    });
    try {
      if (enabled) {
        final deliveryReady = await NotificationService.instance
            .requestPermissionAndEnable();
        if (!mounted) return;
        setState(() {
          _notificationsEnabled = true;
          _pushDeliveryReady = deliveryReady;
          _notificationMessage = deliveryReady
              ? 'Đã bật thông báo cho thiết bị này.'
              : 'Đã cấp quyền trên điện thoại. Backend cần cấu hình Firebase Admin để gửi thông báo.';
        });
      } else {
        await NotificationService.instance.disable();
        if (!mounted) return;
        setState(() {
          _notificationsEnabled = false;
          _pushDeliveryReady = null;
          _notificationMessage = 'Đã tắt thông báo cho thiết bị này.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = false;
        _notificationMessage = error.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) setState(() => _notificationsBusy = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _accessKey.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_testing || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _connectionMessage = null;
    });
    final candidate = _url.text.trim().replaceFirst(RegExp(r'/+$'), '');
    final key = _accessKey.text.trim();
    try {
      final status = await ApiService().getDeviceStatus(
        serverUrl: candidate,
        candidateKey: key,
      );
      if (!mounted) return;
      await ApiService().saveConnectionAddress(
        candidate,
        serverUrl: candidate,
        candidateKey: key,
      );
      await ApiService().setBaseUrl(candidate, candidateKey: key);
      if (!mounted) return;
      setState(() {
        _connectionOk = true;
        _connectionMessage = status.online
            ? 'Đã kết nối. Thiết bị đang trực tuyến.'
            : 'Đã kết nối máy chủ. Thiết bị hiện ngoại tuyến.';
      });
      widget.onRefresh();
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

  @override
  Widget build(BuildContext context) => PageContent(
    child: ListView(
      padding: AppTheme.pagePadding,
      children: [
        const FeederHero(
          title: 'Cài đặt',
          subtitle: 'Tùy chỉnh thiết bị và ứng dụng.',
          icon: Icons.settings_rounded,
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
                        'Kết nối máy chủ',
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
                  'Dùng địa chỉ trong mạng nội bộ hoặc URL HTTPS của máy chủ triển khai.',
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
                TextFormField(
                  controller: _accessKey,
                  enabled: !_testing,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  onFieldSubmitted: (_) => _connect(),
                  decoration: const InputDecoration(
                    labelText: 'Khóa truy cập (nếu có)',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                  validator: (value) {
                    if ((value?.trim().isNotEmpty ?? false) &&
                        Uri.tryParse(_url.text.trim())?.scheme != 'https') {
                      return 'Khóa truy cập cần địa chỉ HTTPS.';
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
        const SizedBox(height: 16),
        SectionCard(
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
                      Icons.notifications_active_outlined,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Thông báo',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                !NotificationService.instance.supportedPlatform
                    ? 'Thông báo đẩy dùng trên Android và iOS.'
                    : !NotificationService.instance.configured
                    ? 'Cần cấu hình Firebase cho App trước khi bật thông báo. Xem docs/FCM_NOTIFICATIONS.md.'
                    : 'Nhận cảnh báo ngay cả khi App đang chạy nền.',
                style: const TextStyle(color: AppTheme.textMuted, height: 1.5),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cho phép thông báo đẩy'),
                subtitle: Text(
                  _notificationsBusy
                      ? 'Đang cập nhật…'
                      : _notificationsEnabled && _pushDeliveryReady == false
                      ? 'Đã có quyền điện thoại; máy chủ chưa bật dịch vụ gửi.'
                      : 'Cảnh báo phiên cấp bị gián đoạn cần xác nhận.',
                ),
                value: _notificationsEnabled,
                onChanged:
                    _notificationsBusy ||
                        !NotificationService.instance.supportedPlatform ||
                        !NotificationService.instance.configured
                    ? null
                    : _setNotificationsEnabled,
              ),
              if (_notificationMessage != null) ...[
                const SizedBox(height: 4),
                Text(
                  _notificationMessage!,
                  style: TextStyle(
                    color: _notificationMessage!.startsWith('Đã')
                        ? AppTheme.accentGreen
                        : AppTheme.accentCoral,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        SafetySettings(
          key: ValueKey(ApiService().baseUrl),
          onSaved: widget.onRefresh,
        ),
        const SizedBox(height: 16),
        const SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PetFeeder',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'ESP32 · Servo cấp thức ăn · HX711 cân bát · MQTT và REST API · Lịch chạy trên thiết bị khi mất mạng.',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 13,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
