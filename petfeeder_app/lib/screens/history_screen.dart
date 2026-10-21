import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<FeedingRecord> _records = [];
  bool _loading = true;
  bool _failed = false;
  bool _clearing = false;
  final _retrying = <String>{};

  Future<void> _complete(FeedingRecord record) async {
    if (_retrying.contains(record.id)) return;
    final remaining = record.targetPortionG - record.actualWeightG!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cấp phần còn thiếu?'),
        content: Text(
          'Chỉ yêu cầu thêm ${remaining.toStringAsFixed(1)} g. Khoảng chờ và các giới hạn an toàn vẫn được áp dụng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gửi yêu cầu'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _retrying.add(record.id));
    try {
      final result = await ApiService().feedNow(
        portion: remaining,
        override: false,
        retryOf: record.id,
      );
      if (!mounted) return;
      showFeedback(
        context,
        result['success'] == true
            ? 'Đã nhận yêu cầu cấp phần còn thiếu; chờ thiết bị xác nhận.'
            : 'Chưa thể cấp thêm. Kiểm tra khoảng chờ, giới hạn và trạng thái thiết bị.',
        error: result['success'] != true,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        showFeedback(
          context,
          error is FeedRequestException
              ? error.message
              : error is StateError
              ? error.message.toString()
              : 'Chưa xác định kết quả. Kiểm tra kết nối và dùng Gửi lại cùng mã.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _retrying.remove(record.id));
    }
  }

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
          'Ẩn các bữa ăn khỏi nhật ký. Dữ liệu chống lặp và hạn mức ngày vẫn được giữ.',
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
    'SENSOR_ERROR' => ('Lỗi cảm biến', AppTheme.accentCoral),
    'QUEUED' => ('Chờ thiết bị nhận', AppTheme.accentAmber),
    'ACCEPTED' => ('Thiết bị đã nhận', AppTheme.accentAmber),
    'DISPENSING' => ('Đang cấp', AppTheme.accentAmber),
    'PARTIAL' => ('Cấp thiếu', AppTheme.accentAmber),
    'TIMEOUT' => ('Hết thời gian cấp', AppTheme.accentCoral),
    'OVER_PORTION' => ('Vượt khẩu phần', AppTheme.accentCoral),
    'INTERRUPTED' => ('Bị gián đoạn', AppTheme.accentCoral),
    'REJECTED' => ('Đã từ chối', AppTheme.accentAmber),
    'COMMAND_EXPIRED' => ('Lệnh hết hạn', AppTheme.accentAmber),
    'DELIVERY_UNKNOWN' => ('Chưa rõ kết quả', AppTheme.accentAmber),
    _ => (value, AppTheme.textMuted),
  };

  (String, IconData) _source(String value) => switch (value.toLowerCase()) {
    'app' => ('Từ ứng dụng', Icons.phone_android_rounded),
    'schedule' => ('Theo lịch ăn', Icons.schedule_rounded),
    'button' => ('Nút trên thiết bị', Icons.touch_app_rounded),
    'override' => ('Cho ăn bổ sung', Icons.restaurant_rounded),
    _ => ('Thiết bị', Icons.pets_rounded),
  };

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
          if (['PARTIAL', 'JAM_ERROR', 'TIMEOUT'].contains(r.status) &&
              r.actualWeightG != null &&
              r.targetPortionG - r.actualWeightG! >= 1)
            TextButton.icon(
              onPressed: _retrying.contains(r.id) ? null : () => _complete(r),
              icon: const Icon(Icons.restaurant_rounded),
              label: const Text('Cấp phần còn thiếu'),
            ),
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
