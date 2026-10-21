import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';
import 'camera_demo_screen.dart';
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
  bool _testing = false;
  String? _connectionMessage;
  bool _connectionOk = false;

  @override
  void initState() {
    super.initState();
    _url.text = ApiService().baseUrl;
  }

  @override
  void dispose() {
    _url.dispose();
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
    try {
      final status = await ApiService().getDeviceStatus(serverUrl: candidate);
      if (!mounted) return;
      await ApiService().setBaseUrl(candidate);
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
        const PageHeading(
          title: 'Kết nối & cài đặt',
          subtitle: 'Thiết lập máy chủ và chính sách cấp thức ăn.',
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
                      child: const Icon(Icons.wifi_rounded, color: AppTheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Kết nối máy chủ',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Điện thoại và máy chủ cần truy cập được cùng mạng.',
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
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_find_rounded),
                    label: Text(_testing ? 'Đang kết nối…' : 'Lưu kết nối'),
                  ),
                ),
                if (_connectionMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _connectionMessage!,
                    style: TextStyle(
                      color: _connectionOk ? AppTheme.accentGreen : AppTheme.accentCoral,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: const Text('Tùy chọn phát triển', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Máy tính này'),
                          onPressed: _testing ? null : () => _url.text = 'http://localhost:3000',
                        ),
                        ActionChip(
                          label: const Text('Giả lập Android'),
                          onPressed: _testing ? null : () => _url.text = 'http://10.0.2.2:3000',
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SafetySettings(
          key: ValueKey(ApiService().baseUrl),
          onSaved: widget.onRefresh,
        ),
        const SizedBox(height: 20),
        SectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              backgroundColor: AppTheme.primaryLight,
              child: Icon(Icons.camera_alt_rounded, color: AppTheme.primary),
            ),
            title: const Text('Camera AI · YOLO'),
            subtitle: const Text('Mở camera để nhận diện chó/mèo và gửi kết quả mới cho thiết bị.'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CameraDemoScreen()),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PetFeeder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text(
                'ESP32 · Servo cấp thức ăn · HX711 cân bát · MQTT và REST API · Lịch chạy trên thiết bị khi mất mạng.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.7),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
