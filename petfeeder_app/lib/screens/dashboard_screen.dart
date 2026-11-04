import 'package:flutter/material.dart';
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

  Future<void> _feed() async {
    if (_submitting || widget.status?.online != true) return;
    setState(() => _submitting = true);
    Map<String, dynamic>? result;
    try {
      result = await ApiService().feedNow(portion: _portion);
      if (!mounted) return;
      if (result['success'] == true) {
        showFeedback(
          context,
          result['message'] as String,
          error: result['code'] == 'AWAITING_DEVICE_RESULT',
        );
        await widget.onRefresh();
      }
    } catch (error) {
      if (mounted) {
        showFeedback(
          context,
          error is FeedRequestException
              ? error.message
              : 'Chưa nhận được kết quả. Kiểm tra trạng thái thiết bị trước khi gửi yêu cầu tiếp theo.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    if (!mounted || result == null || result['success'] == true) return;
    final duplicate = [
      'BLOCKED_DUPLICATE',
      'COOLDOWN',
    ].contains(result['code']);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          duplicate ? Icons.timer_outlined : Icons.info_outline_rounded,
          color: AppTheme.accentAmber,
        ),
        title: Text(duplicate ? 'Bữa ăn vừa được cấp' : 'Chưa thể cho ăn'),
        content: Text(
          duplicate
              ? 'Vui lòng đợi hết khoảng chờ bảo vệ rồi mới cho ăn tiếp.'
              : result!['message'] as String,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  String _systemLabel(String value) => switch (value.trim().toUpperCase()) {
    'CONFIG_APPLIED' => 'Đã đồng bộ cài đặt',
    'CLOCK_SYNCED' => 'Đã đồng bộ giờ thiết bị',
    'TIME_INVALID' => 'Giờ thiết bị chưa đồng bộ',
    'DELIVERY_UNKNOWN' => 'Đang chờ thiết bị xác nhận kết quả',
    'SAN SANG' => 'Sẵn sàng cho bữa ăn',
    'DANG CHO AN' || 'DANG CHO AN...' => 'Đang cấp thức ăn',
    'HOAN TAT' || 'HOAN TAT!' => 'Đã hoàn tất bữa ăn',
    'BOWL_MISSING' => 'Không phát hiện bát trên cân',
    'WEIGHT_UNSTABLE' || 'MEASUREMENT_LOST' => 'Cân chưa ổn định',
    'DAILY_LIMIT' => 'Đã đạt giới hạn lượng ăn trong ngày',
    'DAILY_FEED_LIMIT' => 'Đã đạt số bữa tối đa trong ngày',
    'BOWL_FULL' => 'Bát không còn đủ sức chứa',
    'BLOCKED_DUPLICATE' => 'Đã chặn yêu cầu gửi trùng',
    'RECONCILIATION_REQUIRED' => 'Cần kiểm tra thiết bị trước khi cấp tiếp',
    'COMMAND_EXPIRED' => 'Yêu cầu đã hết hạn',
    'OVER_PORTION' => 'Đã dừng để tránh cấp quá lượng đặt',
    'PARTIAL' => 'Lượng hạt cấp chưa đủ',
    'SENSOR_ERROR' => 'Cần kiểm tra cảm biến',
    'COOLDOWN' => 'Đang trong khoảng chờ bảo vệ',
    'TIMEOUT' => 'Đã dừng sau thời gian cấp tối đa',
    'INTERRUPTED' => 'Phiên cấp bị gián đoạn',
    'DANG CAP' => 'Đang cấp thức ăn',
    'KHOI DONG' => 'Thiết bị đang khởi động',
    'KET NOI WIFI...' => 'Thiết bị đang kết nối Wi-Fi',
    _ => value,
  };

  Widget _metric({
    required String title,
    required String value,
    required String footnote,
    required IconData icon,
    required Color iconColor,
  }) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(25),
      border: Border.all(color: AppTheme.border),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: AppTheme.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              Text(
                footnote,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textLight, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final online = status?.online == true;
    final maxPortion = status?.maxPortionG ?? 100;
    final selectedPortion = _portion
        .clamp(maxPortion < 10 ? maxPortion : 10, maxPortion)
        .toInt();
    final bowlKnown = online && status?.bowlWeightG != null;
    final hopperKnown = online && status?.foodLevelPercent != null;

    return PageContent(
      child: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppTheme.pagePadding,
          children: [
            FeederHero(
              title: 'Cho ăn',
              subtitle: online && status != null
                  ? _systemLabel(status.systemStatus)
                  : 'Bữa ăn của bé, chỉ một chạm.',
              icon: Icons.rice_bowl_rounded,
              badge: online ? 'Đang kết nối' : 'Ngoại tuyến',
            ),
            if (widget.isLoading && status == null) ...[
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 12),
            ],
            if (!online)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, color: AppTheme.primaryDark),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Kiểm tra nguồn điện, Wi-Fi và địa chỉ máy chủ trong Cài đặt.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(1) > 1.1;
                final wide = constraints.maxWidth >= 330 && !largeText;
                final bowl = _metric(
                  title: 'Thức ăn trong bát',
                  value: bowlKnown
                      ? '${status!.bowlWeightG!.toStringAsFixed(1)} g'
                      : '—',
                  footnote: bowlKnown
                      ? 'Sức chứa ${status!.bowlCapacityG} g'
                      : 'Đang chờ số cân mới',
                  icon: Icons.rice_bowl_outlined,
                  iconColor: AppTheme.primaryDark,
                );
                final hopper = _metric(
                  title: 'Thức ăn trong hộp',
                  value: hopperKnown ? '${status!.foodLevelPercent}%' : '—',
                  footnote: hopperKnown
                      ? status!.distanceCm == null
                            ? 'Ước tính từ cảm biến'
                            : 'Cách mặt hạt ${status.distanceCm!.toStringAsFixed(1)} cm'
                      : 'Đang chờ số đo cảm biến',
                  icon: Icons.inventory_2_outlined,
                  iconColor: AppTheme.primaryDark,
                );
                if (wide) {
                  return Row(
                    children: [
                      Expanded(child: bowl),
                      const SizedBox(width: 12),
                      Expanded(child: hopper),
                    ],
                  );
                }
                return Column(
                  children: [bowl, const SizedBox(height: 10), hopper],
                );
              },
            ),
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.restaurant_menu_rounded,
                        color: AppTheme.primaryDark,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Cho ăn thủ công',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chọn lượng hạt cần cấp vào bát.',
                    style: TextStyle(color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hôm nay: ${status?.dailyDispensedG.toStringAsFixed(0) ?? '0'} g  ·  ${status?.dailyFeedCount ?? 0}/${status?.maxDailyFeeds ?? 6} lần',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 14),
                  PortionSelector(
                    value: selectedPortion,
                    max: maxPortion,
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _portion = value),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const ValueKey('feed-now'),
                      onPressed: !online || _submitting || widget.isLoading
                          ? null
                          : () {
                              _portion = selectedPortion;
                              _feed();
                            },
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.rice_bowl_rounded),
                      label: Text(
                        _submitting
                            ? 'Đang gửi yêu cầu…'
                            : 'Cho ăn · $selectedPortion g',
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    online
                        ? 'Thiết bị vẫn áp dụng khoảng chờ, giới hạn ngày và kiểm tra cân.'
                        : 'Kết nối thiết bị để gửi yêu cầu cho ăn từ xa.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                      height: 1.45,
                    ),
                  ),
                  if (status?.sensorMode == 'DEMO_AUTO')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Số liệu cân đang được mô phỏng.',
                        style: TextStyle(
                          color: AppTheme.accentAmber,
                          fontSize: 12,
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
