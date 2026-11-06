import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';

class SchedulesScreen extends StatefulWidget {
  final int refreshToken;
  const SchedulesScreen({super.key,this.refreshToken=0});
  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  List<FeedingSchedule> _schedules = [];
  final _busy = <String>{};
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SchedulesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(widget.refreshToken!=oldWidget.refreshToken)_load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final list = await ApiService().getSchedules();
      if (mounted) {
        setState(
          () => _schedules = list..sort((a, b) => a.time.compareTo(b.time)),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(FeedingSchedule s) async {
    if (_busy.contains(s.id)) return;
    setState(() => _busy.add(s.id));
    try {
      final updated = await ApiService().toggleSchedule(s.id);
      if (!mounted) return;
      setState(() {
        final i = _schedules.indexWhere((item) => item.id == s.id);
        if (i >= 0) _schedules[i] = updated;
      });
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Chưa cập nhật được lịch. Hãy thử lại.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(s.id));
    }
  }

  Future<void> _delete(FeedingSchedule s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa lịch ăn?'),
        content: Text('Lịch “${s.name}” lúc ${s.time} sẽ được xóa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Giữ lại'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Xóa lịch',
              style: TextStyle(color: AppTheme.accentCoral),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy.add(s.id));
    try {
      if (!await ApiService().deleteSchedule(s.id)) throw Exception('delete');
      if (!mounted) return;
      setState(() => _schedules.removeWhere((item) => item.id == s.id));
      showFeedback(context, 'Đã xóa lịch ăn.');
    } catch (_) {
      if (mounted) {
        showFeedback(context, 'Chưa xóa được lịch. Hãy thử lại.', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(s.id));
    }
  }

  Future<void> _add() async {
    final created = await showModalBottomSheet<FeedingSchedule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ScheduleEditor(),
    );
    if (!mounted || created == null) return;
    setState(() {
      _schedules.add(created);
      _schedules.sort((a, b) => a.time.compareTo(b.time));
    });
    showFeedback(context, 'Đã lưu lịch ăn lúc ${created.time}.');
  }

  IconData _mealIcon(String time) {
    final hour = int.tryParse(time.split(':').first) ?? 12;
    if (hour < 10) return Icons.wb_twilight_rounded;
    if (hour < 16) return Icons.wb_sunny_outlined;
    if (hour < 20) return Icons.cloud_rounded;
    return Icons.nightlight_round;
  }

  Widget _scheduleCard(FeedingSchedule s) => SectionCard(
    child: Column(
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.all(Radius.circular(18)),
              ),
              child: Icon(
                _mealIcon(s.time),
                color: AppTheme.primaryDark,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${s.time}  ·  ${s.days.length == 7 ? 'Mỗi ngày' : s.days.join(' · ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Semantics(
              label: 'Bật lịch ${s.name}',
              child: Switch(
                value: s.enabled,
                onChanged: _busy.contains(s.id) ? null : (_) => _toggle(s),
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: AppTheme.border),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.1;
            final portion = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.rice_bowl_outlined,
                  color: AppTheme.textMain,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${s.portionG} g',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            );
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusPill(
                  label: s.enabled ? 'Đang bật' : 'Đã tạm dừng',
                  color: s.enabled ? AppTheme.accentGreen : AppTheme.textMuted,
                  icon: s.enabled ? Icons.check_rounded : Icons.pause_rounded,
                ),
                IconButton(
                  tooltip: 'Xóa lịch ${s.name}',
                  onPressed: _busy.contains(s.id) ? null : () => _delete(s),
                  icon: const Icon(Icons.delete_outline_rounded, size: 21),
                ),
              ],
            );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: Alignment.centerLeft, child: portion),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              children: [portion, const Spacer(), actions],
            );
          },
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PageContent(
    child: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: AppTheme.pagePadding,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          FeederHero(
            title: 'Kế hoạch cho ăn',
            subtitle: 'Thiết lập giờ ăn cho thú cưng.',
            icon: Icons.schedule_rounded,
            badge:
                '${_schedules.where((schedule) => schedule.enabled).length} lịch bật',
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed)
            EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Chưa tải được lịch ăn',
              message: 'Kiểm tra kết nối và thử tải lại.',
              action: OutlinedButton(
                onPressed: _load,
                child: const Text('Thử lại'),
              ),
            )
          else ...[
            if (_schedules.isEmpty)
              const EmptyState(
                icon: Icons.schedule_rounded,
                title: 'Chưa có lịch cho ăn',
                message:
                    'Thêm giờ ăn và khẩu phần. PetFeeder sẽ giúp bạn chăm bé đều đặn.',
              )
            else
              ..._schedules.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _scheduleCard(s),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Thêm lịch mới'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ScheduleEditor extends StatefulWidget {
  const _ScheduleEditor();
  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  final _name = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  int _portion = 35;
  bool _saving = false;
  String? _error;
  static const _week = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  final _days = _week.toSet();
  String get _timeText =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _days.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ApiService().createSchedule(
        name: _name.text.trim().isEmpty
            ? 'Bữa ăn $_timeText'
            : _name.text.trim(),
        time: _timeText,
        portionG: _portion,
        days: _week.where(_days.contains).toList(),
        enabled: true,
      );
      if (mounted) Navigator.pop(context, created);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Chưa lưu được lịch. Kiểm tra kết nối rồi thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: PageHeading(
                      title: 'Thêm lịch ăn',
                      subtitle: 'Chọn giờ, khẩu phần và ngày lặp lại.',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng biểu mẫu',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.background,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              TextField(
                controller: _name,
                enabled: !_saving,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tên bữa ăn',
                  hintText: 'Ví dụ: Bữa sáng',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: const BorderSide(color: AppTheme.border),
                ),
                leading: const Icon(
                  Icons.schedule_rounded,
                  color: AppTheme.primary,
                ),
                title: const Text('Giờ ăn'),
                subtitle: Text(
                  _timeText,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _saving
                    ? null
                    : () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _time,
                        );
                        if (mounted && picked != null) {
                          setState(() => _time = picked);
                        }
                      },
              ),
              const SizedBox(height: 20),
              PortionSelector(
                value: _portion,
                max: 120,
                onChanged: _saving ? null : (v) => setState(() => _portion = v),
              ),
              const Text(
                'Lặp lại vào',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _week
                    .map(
                      (d) => FilterChip(
                        label: Text(d),
                        selected: _days.contains(d),
                        labelStyle: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w700,
                          color: _days.contains(d)
                              ? Colors.white
                              : AppTheme.textMain,
                        ),
                        onSelected: _saving
                            ? null
                            : (selected) => setState(
                                () => selected ? _days.add(d) : _days.remove(d),
                              ),
                      ),
                    )
                    .toList(),
              ),
              if (_days.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Chọn ít nhất một ngày.',
                    style: TextStyle(color: AppTheme.accentCoral),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppTheme.accentCoral),
                  ),
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || _days.isEmpty ? null : _save,
                  child: Text(_saving ? 'Đang lưu…' : 'Lưu lịch ăn'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
