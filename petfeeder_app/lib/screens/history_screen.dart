import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';

class HistoryScreen extends StatefulWidget {
  final Future<void> Function() onRefresh;
  const HistoryScreen({super.key, required this.onRefresh});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<FeedingRecord> _records = [];
  bool _loading = true;
  bool _failed = false;
  bool _showAll = false;
  bool _todayOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final rows = await ApiService().getFeedingHistory(limit: 100);
      if (mounted) setState(() => _records = rows);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isToday(FeedingRecord row) =>
      row.occurredAt != null &&
      DateUtils.isSameDay(row.occurredAt!.toLocal(), DateTime.now());

  bool _hasMeasuredResult(FeedingRecord row) =>
      row.actualWeightG != null &&
      const {
        'SUCCESS',
        'HOAN TAT',
        'PARTIAL',
        'OVER_PORTION',
        'SENSOR_ERROR',
        'INTERRUPTED',
        'TIMEOUT',
      }.contains(row.status.toUpperCase());

  String _time(DateTime? value) {
    if (value == null) return 'Không rõ giờ';
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _dayAndTime(DateTime? value) {
    if (value == null) return 'Không rõ thời gian';
    final local = value.toLocal();
    final today = DateUtils.isSameDay(local, DateTime.now());
    final yesterday = DateUtils.isSameDay(
      local,
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final prefix = today
        ? 'Hôm nay'
        : yesterday
        ? 'Hôm qua'
        : '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}';
    return '$prefix · ${_time(local)}';
  }

  String _sourceLabel(String source) => switch (source.toUpperCase()) {
    'BUTTON' => 'Nút trên mạch',
    'SCHEDULE' => 'Theo lịch',
    _ => 'Qua ứng dụng',
  };

  ({String label, Color color, IconData icon}) _state(FeedingRecord row) {
    final status = row.status.toUpperCase();
    if (status == 'SUCCESS' || status == 'HOAN TAT') {
      return (
        label: 'Hoàn tất',
        color: AppTheme.accentGreen,
        icon: Icons.check_rounded,
      );
    }
    if (status == 'QUEUED' ||
        status == 'DISPENSING' ||
        status == 'DELIVERY_UNKNOWN') {
      return (
        label: 'Đang xử lý',
        color: AppTheme.accentAmber,
        icon: Icons.schedule_rounded,
      );
    }
    if (status == 'PARTIAL') {
      return (
        label: 'Cấp chưa đủ',
        color: AppTheme.accentAmber,
        icon: Icons.info_outline_rounded,
      );
    }
    return (
      label: 'Không hoàn tất',
      color: AppTheme.accentCoral,
      icon: Icons.close_rounded,
    );
  }

  Widget _summaryMetric(String label, String value, IconData icon) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.all(Radius.circular(15)),
          ),
          child: Icon(icon, color: AppTheme.primaryDark, size: 23),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );

  Widget _recordTile(FeedingRecord row) {
    final state = _state(row);
    final icon = switch (row.source.toUpperCase()) {
      'BUTTON' => Icons.touch_app_rounded,
      'SCHEDULE' => Icons.schedule_rounded,
      _ => Icons.rice_bowl_rounded,
    };
    final actual = row.actualWeightG;
    final portion = row.targetPortionG;
    final amount = actual != null
        ? '${actual.toStringAsFixed(0)} g thực cấp'
        : portion != null
        ? '${portion.toStringAsFixed(0)} g yêu cầu'
        : 'Chưa có số cân';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            child: Icon(icon, color: AppTheme.primaryDark, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sourceLabel(row.source),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _dayAndTime(row.occurredAt),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  amount,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          StatusPill(label: state.label, color: state.color, icon: state.icon),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _records.where(_isToday).toList();
    final measured = today.where(_hasMeasuredResult).toList();
    final meals = measured.length;
    final totalGrams = measured.fold<double>(
      0,
      (sum, row) => sum + (row.actualWeightG ?? 0),
    );
    final latest = today.isEmpty ? null : today.first.occurredAt;
    final filtered = (_todayOnly ? today : _records).toList();
    final visible = _showAll ? filtered : filtered.take(5).toList();

    return PageContent(
      child: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await widget.onRefresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppTheme.pagePadding,
          children: [
            FeederHero(
              title: 'Lịch sử cho ăn',
              subtitle: 'Theo dõi các lần cấp thức ăn gần đây.',
              icon: Icons.receipt_long_rounded,
              badge: 'Hôm nay',
            ),
            SectionCard(
              child: Row(
                children: [
                  _summaryMetric(
                    'Tổng lần ăn',
                    '$meals lần',
                    Icons.rice_bowl_outlined,
                  ),
                  Container(width: 1, height: 66, color: AppTheme.border),
                  const SizedBox(width: 14),
                  _summaryMetric(
                    'Đã cấp',
                    '${totalGrams.toStringAsFixed(0)} g',
                    Icons.grain_rounded,
                  ),
                  Container(width: 1, height: 66, color: AppTheme.border),
                  const SizedBox(width: 14),
                  _summaryMetric(
                    'Lần gần nhất',
                    _time(latest),
                    Icons.access_time_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Các lần cho ăn',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      PopupMenuButton<bool>(
                        tooltip: 'Lọc lịch sử',
                        initialValue: _todayOnly,
                        onSelected: (value) => setState(() {
                          _todayOnly = value;
                          _showAll = false;
                        }),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: true, child: Text('Hôm nay')),
                          PopupMenuItem(value: false, child: Text('Tất cả')),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.border),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.filter_list_rounded, size: 18),
                              const SizedBox(width: 5),
                              Text(_todayOnly ? 'Hôm nay' : 'Tất cả'),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_failed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: EmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Chưa tải được lịch sử',
                        message: 'Kiểm tra kết nối rồi thử lại.',
                        action: OutlinedButton(
                          onPressed: _load,
                          child: const Text('Thử lại'),
                        ),
                      ),
                    )
                  else if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: EmptyState(
                        icon: Icons.rice_bowl_outlined,
                        title: 'Chưa có lần cho ăn nào',
                        message: _todayOnly
                            ? 'Các lần cấp thức ăn trong hôm nay sẽ hiện ở đây.'
                            : 'Lịch sử sẽ hiện sau khi thiết bị ghi nhận lần cấp đầu tiên.',
                      ),
                    )
                  else ...[
                    const SizedBox(height: 8),
                    for (var i = 0; i < visible.length; i++) ...[
                      _recordTile(visible[i]),
                      if (i < visible.length - 1)
                        const Divider(height: 1, color: AppTheme.border),
                    ],
                    if (filtered.length > 5)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => setState(() => _showAll = !_showAll),
                          child: Text(
                            _showAll ? 'Thu gọn lịch sử' : 'Xem thêm lịch sử',
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
