import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';

class SafetySettings extends StatefulWidget {
  final VoidCallback onSaved;
  const SafetySettings({super.key, required this.onSaved});

  @override
  State<SafetySettings> createState() => _SafetySettingsState();
}

class _SafetySettingsState extends State<SafetySettings> {
  static const fields = <String, String>{
    'max_portion_g': 'Khẩu phần tối đa mỗi lần (g)',
    'daily_limit_g': 'Tổng lượng tối đa mỗi ngày (g)',
    'max_daily_feeds': 'Số lần cấp tối đa mỗi ngày',
    'bowl_capacity_g': 'Sức chứa tối đa của bát (g)',
    'max_feed_pulses': 'Số nhịp servo tối đa mỗi phiên',
    'min_interval_s': 'Khoảng chờ giữa các phiên (giây)',
    'feed_timeout_s': 'Thời gian cấp tối đa (giây)',
    'tolerance_g': 'Sai số cân (g)',
    'timezone_offset_min': 'Múi giờ so với UTC (phút)',
  };

  final values = {for (final key in fields.keys) key: TextEditingController()};
  bool requirePet = false;
  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final config = await ApiService().getSafetyConfig();
      if (!mounted) return;
      for (final key in fields.keys) {
        values[key]!.text = '${config[key]}';
      }
      setState(() {
        requirePet = config['require_pet'] == true;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final patch = <String, dynamic>{'require_pet': requirePet};
      for (final key in fields.keys) {
        final parsed = key == 'tolerance_g'
            ? num.tryParse(values[key]!.text.trim())
            : int.tryParse(values[key]!.text.trim());
        if (parsed == null) {
          throw FormatException('Nhập giá trị hợp lệ cho ${fields[key]}');
        }
        patch[key] = parsed;
      }
      await ApiService().saveSafetyConfig(patch);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu; chờ ESP32 áp dụng cấu hình.')),
      );
      widget.onSaved();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in values.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Chính sách cấp thức ăn',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Khẩu phần là lượng cấp thêm vào bát. Các giới hạn được kiểm tra ở backend và ESP32.',
          style: TextStyle(color: AppTheme.textMuted, height: 1.5),
        ),
        const SizedBox(height: 12),
        if (loading)
          const LinearProgressIndicator()
        else ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bắt buộc camera phát hiện chó/mèo'),
            subtitle: const Text(
              'Cần mở camera và nhận diện mới từ YOLO trước khi cấp. Chức năng này chỉ nhận biết loài chó/mèo, chưa xác minh đúng cá thể đã đăng ký.',
            ),
            value: requirePet,
            onChanged: saving ? null : (value) => setState(() => requirePet = value),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: const Text('Giới hạn và lịch hệ thống'),
            children: [
              for (final key in fields.keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: values[key],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: fields[key]),
                  ),
                ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Đang lưu…' : 'Lưu chính sách'),
              ),
              TextButton(onPressed: saving ? null : load, child: const Text('Tải lại')),
            ],
          ),
        ],
      ],
    ),
  );
}
