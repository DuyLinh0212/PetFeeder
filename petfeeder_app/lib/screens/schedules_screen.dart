import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key});

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  List<FeedingSchedule> _schedules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() => _isLoading = true);
    try {
      final list = await ApiService().getSchedules();
      setState(() => _schedules = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải lịch: $e'), backgroundColor: AppTheme.accentCoral),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleToggle(FeedingSchedule s) async {
    try {
      final updated = await ApiService().toggleSchedule(s.id);
      if (!mounted) return;
      setState(() {
        final idx = _schedules.indexWhere((item) => item.id == s.id);
        if (idx != -1) _schedules[idx] = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${updated.enabled ? "Đã bật" : "Đã tắt"} lịch ${updated.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi cập nhật: $e'), backgroundColor: AppTheme.accentCoral),
      );
    }
  }

  Future<void> _handleDelete(FeedingSchedule s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xác nhận xóa lịch'),
        content: Text('Bạn có chắc chắn muốn xóa "${s.name}" (${s.time}) không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: AppTheme.accentCoral, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ApiService().deleteSchedule(s.id);
        if (!mounted) return;
        setState(() => _schedules.removeWhere((item) => item.id == s.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa lịch cho ăn thành công')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xóa lịch: $e'), backgroundColor: AppTheme.accentCoral),
        );
      }
    }
  }

  void _showAddScheduleSheet() {
    TimeOfDay selectedTime = const TimeOfDay(hour: 7, minute: 0);
    int selectedPortion = 35;
    final nameController = TextEditingController(text: 'Bữa ăn');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final timeStr =
              '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              top: 24,
              left: 20,
              right: 20,
            ),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.add_alarm_rounded, color: AppTheme.primary, size: 26),
                    const SizedBox(width: 10),
                    const Text(
                      'Thêm lịch cho ăn mới',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Tên bữa ăn (vd: Bữa sáng, Bữa xế)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(context: ctx, initialTime: selectedTime);
                    if (picked != null) {
                      setSheetState(() => selectedTime = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(14),
                      color: AppTheme.background,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded, color: AppTheme.primary),
                        const SizedBox(width: 12),
                        const Text('Giờ cho ăn:', style: TextStyle(fontWeight: FontWeight.w500)),
                        const Spacer(),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.edit, size: 16, color: AppTheme.textMuted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Khẩu phần ăn:', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '$selectedPortion gram',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    ),
                  ],
                ),
                Slider(
                  value: selectedPortion.toDouble(),
                  min: 10,
                  max: 120,
                  divisions: 22,
                  activeColor: AppTheme.primary,
                  onChanged: (val) => setSheetState(() => selectedPortion = val.round()),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        final created = await ApiService().createSchedule(
                          name: nameController.text.trim().isEmpty ? 'Bữa ăn $timeStr' : nameController.text.trim(),
                          time: timeStr,
                          portionG: selectedPortion,
                          days: ["T2", "T3", "T4", "T5", "T6", "T7", "CN"],
                          enabled: true,
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        setState(() => _schedules.add(created));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppTheme.accentGreen,
                            content: Text('Đã thêm lịch $timeStr và đồng bộ xuống ESP32!'),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppTheme.accentCoral),
                        );
                      }
                    },
                    child: const Text('LƯU VÀ ĐỒNG BỘ XUỐNG ESP32'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSchedules,
              child: _schedules.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.schedule_rounded, size: 64, color: AppTheme.textLight),
                          const SizedBox(height: 12),
                          const Text('Chưa có lịch cho ăn nào', style: TextStyle(fontSize: 16, color: AppTheme.textMuted)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _showAddScheduleSheet,
                            icon: const Icon(Icons.add),
                            label: const Text('Tạo lịch đầu tiên'),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      itemCount: _schedules.length + 1,
                      separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
                      itemBuilder: (ctx, idx) {
                        if (idx == _schedules.length) {
                          // Footer button
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton.icon(
                              onPressed: _showAddScheduleSheet,
                              icon: const Icon(Icons.add_alarm_rounded, color: AppTheme.primary),
                              label: const Text('THÊM LỊCH MỚI', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                side: const BorderSide(color: AppTheme.primary),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          );
                        }

                        final s = _schedules[idx];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: s.enabled ? AppTheme.primaryLight : AppTheme.background,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.alarm_rounded,
                                    color: s.enabled ? AppTheme.primary : AppTheme.textLight,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            s.time,
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w900,
                                              color: s.enabled ? AppTheme.textMain : AppTheme.textMuted,
                                              letterSpacing: -0.5,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.background,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: AppTheme.border),
                                            ),
                                            child: Text(
                                              '${s.portionG}g',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        s.name,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: s.enabled ? AppTheme.textMain : AppTheme.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: s.enabled,
                                  activeTrackColor: AppTheme.primary,
                                  onChanged: (val) => _handleToggle(s),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.textLight),
                                  onPressed: () => _handleDelete(s),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
