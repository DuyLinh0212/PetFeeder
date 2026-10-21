import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SafetySettings extends StatefulWidget {
  final VoidCallback onSaved;
  const SafetySettings({super.key, required this.onSaved});
  @override
  State<SafetySettings> createState() => _SafetySettingsState();
}

class _SafetySettingsState extends State<SafetySettings> {
  static const fields = {
    'max_portion_g': 'Tối đa mỗi lần (g)',
    'daily_limit_g': 'Giới hạn mỗi ngày (g)',
    'max_daily_feeds': 'Số lần cấp tối đa mỗi ngày',
    'bowl_capacity_g': 'Sức chứa bát (g)',
    'max_feed_pulses': 'Số nhịp cấp tối đa',
    'min_interval_s': 'Khoảng chờ (giây)',
    'observation_s': 'Theo dõi sau cấp (giây)',
    'food_stale_s': 'Nhắc kiểm tra thức ăn cũ (giây)',
    'feed_timeout_s': 'Thời gian cấp tối đa (giây)',
  };
  final label = TextEditingController();
  final values = {for (final key in fields.keys) key: TextEditingController()};
  bool confirmed = false,
      requirePet = false,
      lockdown = false,
      loading = true,
      saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final c = await ApiService().getSafetyConfig();
      if (!mounted) return;
      for (final key in fields.keys) {
        values[key]!.text = '${c[key]}';
      }
      label.text = c['food_label'] ?? '';
      setState(() {
        confirmed = c['food_confirmed'] == true;
        requirePet = c['require_pet'] == true;
        lockdown = c['lockdown'] == true;
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
      final patch = <String, dynamic>{
        'food_label': label.text.trim(),
        'food_confirmed': confirmed,
        'require_pet': requirePet,
        'lockdown': lockdown,
      };
      for (final key in fields.keys) {
        final number = int.tryParse(values[key]!.text);
        if (number == null) {
          throw FormatException('Nhập số nguyên cho ${fields[key]}');
        }
        patch[key] = number;
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
    label.dispose();
    for (final c in values.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Xác nhận thức ăn và giới hạn cấp',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (loading)
            const LinearProgressIndicator()
          else ...[
            TextField(
              controller: label,
              decoration: const InputDecoration(
                labelText: 'Tên thức ăn do chủ xác nhận',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tôi đã kiểm tra thức ăn'),
              value: confirmed,
              onChanged: saving ? null : (v) => setState(() => confirmed = v!),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Khóa cấp thức ăn'),
              value: lockdown,
              onChanged: saving ? null : (v) => setState(() => lockdown = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Yêu cầu phát hiện chó/mèo trước khi cấp'),
              subtitle: const Text(
                'YOLO phải phát hiện chó/mèo từ ảnh camera mới. Không có kết quả hợp lệ sẽ chặn UNKNOWN_PET.',
              ),
              value: requirePet,
              onChanged: saving ? null : (v) => setState(() => requirePet = v),
            ),
            ExpansionTile(
              title: const Text('Giới hạn và thời gian kiểm thử'),
              children: [
                for (final key in fields.keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: values[key],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: fields[key]),
                    ),
                  ),
              ],
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: saving ? null : save,
                  child: Text(
                    saving ? 'Đang lưu...' : 'Lưu xác nhận và giới hạn',
                  ),
                ),
                TextButton(
                  onPressed: saving ? null : load,
                  child: const Text('Tải lại'),
                ),
              ],
            ),
            const Text(
              'SUCCESS xác nhận lượng máy đã cấp; cân giảm chưa chứng minh thú đã ăn. Phiên gián đoạn cần kiểm tra và gửi reconcile CHECKED trên Serial.',
            ),
          ],
        ],
      ),
    ),
  );
}
