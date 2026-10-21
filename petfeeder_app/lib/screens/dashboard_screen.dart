import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_components.dart';

class DashboardScreen extends StatefulWidget {
  final DeviceStatus? status;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  const DashboardScreen({
    super.key,
    required this.status,
    required this.isLoading,
    required this.onRefresh,
  });
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _portion = 30;
  bool _submitting = false;

  Future<void> _feed({bool override = false}) async {
    if (_submitting || widget.status?.online != true) return;
    setState(() => _submitting = true);
    Map<String, dynamic>? result;
    try {
      result = await ApiService().feedNow(
        portion: _portion,
        override: override,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        showFeedback(context, result['message'] as String);
        await widget.onRefresh();
      }
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Chưa gửi được lệnh. Hãy kiểm tra kết nối rồi thử lại.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (!mounted || result == null || result['success'] == true) return;
    final duplicate = result['code'] == 'BLOCKED_DUPLICATE';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          duplicate ? Icons.timer_outlined : Icons.info_outline_rounded,
          color: AppTheme.accentAmber,
        ),
        title: Text(duplicate ? 'Bữa ăn vừa được cấp' : 'Chưa thể cho ăn'),
        content: Text(result!['message'] as String),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Đóng'),
          ),
          if (duplicate)
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Vẫn cho ăn'),
            ),
        ],
      ),
    );
    // Override is explicit and applies to this request only.
    if (confirmed == true && mounted) await _feed(override: true);
  }

  String _lastMeal(DeviceStatus? status) {
    if (status?.lastFeedTime == null) return 'Chưa có bữa ăn gần đây';
    final date = DateTime.tryParse(status!.lastFeedTime!);
    final time = date == null
        ? status.lastFeedTime!
        : DateFormat('HH:mm · dd/MM').format(date.toLocal());
    return 'Lần gần nhất: $time · ${status.lastFeedPortionG.toStringAsFixed(0)} g';
  }

  String _systemLabel(String value) => switch (value.toUpperCase()) {
    'SAN SANG' => 'Sẵn sàng cho bữa ăn',
    'DANG CHO AN' || 'DANG CHO AN...' => 'Đang cấp thức ăn',
    'HOAN TAT' || 'HOAN TAT!' => 'Đã hoàn tất bữa ăn',
    'KET THUC AN' || 'JAM_ERROR' || 'LOI KET HAT' => 'Thức ăn bị kẹt',
    'HET HAT' || 'EMPTY' || 'LOI: HET HAT' => 'Cần bổ sung thức ăn',
    'LOI: HONG CAN!' => 'Cần kiểm tra cân thức ăn',
    'LOI: CB SIEU AM' => 'Cần kiểm tra cảm biến mức hạt',
    'KHOA AN TOAN!' => 'Thiết bị đang khóa an toàn',
    'CHO XAC MINH' => 'Đang chờ xác minh',
    'VUOT HAN MUC' => 'Đã đạt hạn mức cho ăn',
    'BLOCKED: VUA AN' => 'Bé vừa được cho ăn',
    'MAT BAT THUC AN!' => 'Hãy đặt lại bát thức ăn',
    'CAN KHONG ON DINH' => 'Cân thức ăn chưa ổn định',
    'BAT DA DAY!' => 'Bát thức ăn đã đầy',
    'OVERRIDE FEED' => 'Đang cấp bữa ăn bổ sung',
    'DUNG: THU AN!' => 'Đã dừng cấp hạt khi bé đang ăn',
    'CAP THIEU!' => 'Lượng hạt cấp chưa đủ',
    'XU LY KET!' => 'Đang xử lý hạt bị kẹt',
    'KHOI DONG' => 'Thiết bị đang khởi động',
    'KET NOI WIFI...' => 'Thiết bị đang kết nối Wi-Fi',
    _ => value,
  };

  Widget _metric({
    required String label,
    required String value,
    required IconData icon,
    required String caption,
    bool highlighted = false,
    Color? captionColor,
    double? progress,
  }) {
    final foreground = highlighted ? Colors.white : AppTheme.textMain;
    final muted = highlighted ? const Color(0xFFD4E4DC) : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: highlighted ? AppTheme.primaryDark : AppTheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: highlighted ? null : Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              color: foreground,
              fontSize: 36,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 12),
          if (progress != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                color: const Color(0xFFD5E9A8),
                backgroundColor: Colors.white.withAlpha(30),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            caption,
            style: TextStyle(
              color: captionColor ?? muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final online = status?.online == true;
    final known = status != null && online;
    final percent = (status?.foodLevelPercent ?? 0).clamp(0, 100);
    final low = percent <= 20;
    final food = _metric(
      label: 'Hạt trong hộp',
      value: known ? '$percent%' : '—',
      icon: Icons.inventory_2_outlined,
      highlighted: true,
      caption: !known
          ? 'Chưa có dữ liệu mới'
          : low
          ? 'Cần thêm hạt'
          : percent <= 45
          ? 'Nên chuẩn bị thêm hạt'
          : 'Đủ hạt cho bé',
      captionColor: known && low ? const Color(0xFFFFC4B8) : null,
      progress: known ? percent / 100 : 0,
    );
    final bowl = _metric(
      label: 'Trong bát',
      value: known ? '${status.bowlWeightG.toStringAsFixed(1)} g' : '—',
      icon: Icons.rice_bowl_rounded,
      caption: known ? 'Khối lượng hiện tại' : 'Chưa có dữ liệu mới',
    );
    return PageContent(
      child: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: AppTheme.pagePadding,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const PageHeading(
              title: 'Chăm bé mỗi ngày',
              subtitle: 'Theo dõi thiết bị, chủ động từng bữa ăn.',
            ),
            if (widget.isLoading) ...[
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isLoading && status == null
                              ? 'Đang kết nối…'
                              : online
                              ? 'Đang trực tuyến'
                              : 'Chưa trực tuyến',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          online
                              ? _systemLabel(status!.systemStatus)
                              : 'Kiểm tra nguồn điện, Wi-Fi và địa chỉ trong Cài đặt.',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth /
                        MediaQuery.textScalerOf(context).scale(1) >=
                    300;
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [food, const SizedBox(height: 12), bowl],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: food),
                      const SizedBox(width: 12),
                      Expanded(child: bowl),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.restaurant_rounded,
                        color: AppTheme.primary,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cho ăn ngay',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  PortionSelector(
                    value: _portion,
                    onChanged: _submitting
                        ? null
                        : (v) => setState(() => _portion = v),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: !online || _submitting || widget.isLoading
                          ? null
                          : _feed,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.restaurant_rounded),
                      label: Text(
                        _submitting ? 'Đang gửi…' : 'Cho ăn · $_portion g',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    online
                        ? 'Tự động bảo vệ bé khỏi các bữa ăn quá gần nhau.'
                        : 'Kết nối thiết bị để cho bé ăn từ xa.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastMeal(status),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        height: 1.5,
                      ),
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
}
