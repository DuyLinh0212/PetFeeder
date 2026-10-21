import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/feeding_session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';

class HistoryScreen extends StatefulWidget {
  final FeedingSession session;
  const HistoryScreen({super.key, required this.session});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<FeedingRecord> _records = [];
  bool _loading = true;
  bool _failed = false;
  bool _clearing = false;

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
      final records = await ApiService().getHistory();
      if (mounted) setState(() => _records = records);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa nhật ký?'),
        content: const Text(
          'Toàn bộ lịch sử cho ăn sẽ bị xóa. Bạn không thể khôi phục thao tác này.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Giữ lại'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Xóa nhật ký',
              style: TextStyle(color: AppTheme.accentCoral),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      if (!await ApiService().clearHistory()) throw Exception('clear');
      if (!mounted) return;
      setState(() => _records = []);
      showFeedback(context, 'Đã xóa nhật ký.');
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Chưa xóa được nhật ký. Hãy thử lại.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  String _date(String iso) {
    final date = DateTime.tryParse(iso);
    return date == null
        ? iso
        : DateFormat('HH:mm · dd/MM/yyyy').format(date.toLocal());
  }

  (String, Color) _status(String value) => switch (value.toUpperCase()) {
    'SUCCESS' || 'HOAN TAT' => ('Đã cho ăn', AppTheme.accentGreen),
    'JAM_ERROR' => ('Kẹt thức ăn', AppTheme.accentCoral),
    'EMPTY' || 'FOOD_EMPTY' => ('Hết hạt', AppTheme.accentCoral),
    'BLOCKED' || 'BLOCKED_DUPLICATE' => ('Đã chặn', AppTheme.accentAmber),
    'RESUMED' => ('Đã chuyển sang phiên cấp tiếp', AppTheme.textMuted),
    'PARTIAL' => ('Cấp chưa đủ', AppTheme.accentAmber),
    'PAUSED' => ('Chờ đặt lại bát', AppTheme.accentAmber),
    'INTERRUPTED' => ('Đã dừng', AppTheme.accentCoral),
    'TIMEOUT' => ('Quá thời gian', AppTheme.accentCoral),
    'REJECTED' => ('Đã từ chối', AppTheme.accentAmber),
    'SENSOR_ERROR' => ('Lỗi cảm biến', AppTheme.accentCoral),
    _ => (value, AppTheme.textMuted),
  };

  (String, IconData) _source(String value) => switch (value.toLowerCase()) {
    'app' => ('Từ ứng dụng', Icons.phone_android_rounded),
    'schedule' => ('Theo lịch ăn', Icons.schedule_rounded),
    'button' => ('Nút trên thiết bị', Icons.touch_app_rounded),
    'override' => ('Cho ăn bổ sung', Icons.restaurant_rounded),
    _ => ('Thiết bị', Icons.pets_rounded),
  };

  Future<void> _retry(FeedingRecord r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          r.status == 'PAUSED'
              ? 'Đã đặt lại đúng bát?'
              : 'Cấp tiếp phần còn thiếu?',
        ),
        content: Text(
          r.status == 'PAUSED'
              ? 'Đặt lại đúng bát, giữ nguyên lượng hạt trong bát. Thiết bị sẽ kiểm tra cân trước khi tiếp tục.'
              : 'Kiểm tra hộp hạt và cơ cấu cấp. Chỉ cấp phần còn thiếu của phiên này.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Đóng'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final response = await widget.session.send(
      portion: r.rootTargetG.round(),
      retryOf: r.commandId,
      confirmBowl: r.status == 'PAUSED',
    );
    if (!mounted) return;
    showFeedback(
      context,
      response['success'] == true
          ? 'Đang chờ kết quả cấp tiếp.'
          : response['message'] as String? ?? 'Chưa thể cấp tiếp.',
      error: response['success'] != true,
    );
  }

  Widget _record(FeedingRecord r) {
    final (label, color) = _status(r.status);
    final (source, icon) = _source(r.triggerSource);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _date(r.timestamp),
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              StatusPill(label: label, color: color),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: AppTheme.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.actualWeightG == null
                          ? 'Chưa xác định'
                          : '${r.actualWeightG!.toStringAsFixed(1)} g',
                      style: const TextStyle(
                        fontSize: 26,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Mục tiêu ${r.targetPortionG} g · $source',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (r.errorCode != 'NONE') ...[
            const SizedBox(height: 10),
            Text(
              r.errorCode,
              style: const TextStyle(color: AppTheme.accentCoral),
            ),
          ],
          if (r.commandId != null &&
              r.retryCommandId == null &&
              ((r.measurementValid &&
                      ['JAM_ERROR', 'PARTIAL', 'TIMEOUT'].contains(r.status) &&
                      r.cumulativeDeliveredG != null &&
                      r.rootTargetG - r.cumulativeDeliveredG! >
                          r.portionToleranceG) ||
                  r.status == 'PAUSED'))
            OutlinedButton(
              onPressed:
                  widget.session.posting ||
                      (widget.session.pending &&
                          !(widget.session.paused &&
                              widget.session.id == r.commandId))
                  ? null
                  : () => _retry(r),
              child: const Text('Cấp tiếp phần thiếu'),
            ),
          if (r.commandId != null && r.status == 'PAUSED')
            TextButton(
              onPressed: () async {
                try {
                  final response = await ApiService().cancelCommand(
                    r.commandId!,
                  );
                  if (!mounted) return;
                  showFeedback(
                    context,
                    response['message'] as String? ?? 'Đang chờ xác nhận hủy.',
                  );
                  await widget.session.check();
                  await _load();
                } catch (_) {
                  if (mounted) {
                    showFeedback(context, 'Chưa hủy được phiên.', error: true);
                  }
                }
              },
              child: const Text('Hủy phiên đang chờ'),
            ),
          if (r.message.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              r.message,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PageContent(
    child: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: AppTheme.pagePadding,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const PageHeading(
            title: 'Lịch sử cho ăn',
            subtitle: 'Thời gian, khẩu phần và kết quả từng bữa.',
          ),
          if (widget.session.id != null) ...[
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.session.label),
                  TextButton(
                    onPressed: widget.session.checking
                        ? null
                        : () async {
                            await widget.session.check();
                            if (mounted) await _load();
                          },
                    child: const Text('Kiểm tra kết quả'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed)
            EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Chưa tải được nhật ký',
              message: 'Kết nối lại để xem những bữa ăn gần đây.',
              action: OutlinedButton(
                onPressed: _load,
                child: const Text('Thử lại'),
              ),
            )
          else if (_records.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              title: 'Một khởi đầu mới',
              message: 'Các bữa ăn sẽ xuất hiện ở đây sau khi bạn cho bé ăn.',
            )
          else ...[
            ..._records.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _record(r),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _clearing ? null : _clear,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: Text(_clearing ? 'Đang xóa…' : 'Xóa nhật ký'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    ),
  );
}
