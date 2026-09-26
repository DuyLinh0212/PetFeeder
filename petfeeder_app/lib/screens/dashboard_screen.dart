import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends StatefulWidget {
  final DeviceStatus? status;
  final bool isLoading;
  final VoidCallback onRefresh;

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
  int _selectedPortion = 30;
  bool _isOverride = false;
  bool _isSubmitting = false;

  final List<int> _presetPortions = [20, 30, 45, 60, 80];

  Future<void> _handleFeedNow() async {
    setState(() => _isSubmitting = true);
    try {
      final res = await ApiService().feedNow(
        portion: _selectedPortion,
        override: _isOverride,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.accentGreen,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text(res['message'])),
              ],
            ),
          ),
        );
        widget.onRefresh();
      } else {
        // Có thể bị chặn do ăn trùng (Duplicate Feed Protection)
        _showErrorDialog(
          title: res['code'] == 'BLOCKED_DUPLICATE' ? 'Lệnh bị chặn (Ăn trùng)' : 'Không thể cho ăn',
          message: res['message'],
          isBlockedDuplicate: res['code'] == 'BLOCKED_DUPLICATE',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.accentCoral,
          content: Text('Lỗi kết nối máy chủ: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showErrorDialog({
    required String title,
    required String message,
    bool isBlockedDuplicate = false,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isBlockedDuplicate ? Icons.timer_outlined : Icons.warning_amber_rounded,
              color: isBlockedDuplicate ? AppTheme.accentAmber : AppTheme.accentCoral,
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message),
        actions: [
          if (isBlockedDuplicate)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _isOverride = true);
                _handleFeedNow();
              },
              child: const Text('Ghi đè & Cho ăn ngay', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final isOnline = status?.online ?? false;
    final foodPercent = status?.foodLevelPercent ?? 0;
    final bowlWeight = status?.bowlWeightG ?? 0.0;
    final systemStatus = status?.systemStatus ?? 'DANG KET NOI...';

    return RefreshIndicator(
      onRefresh: () async => widget.onRefresh(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar: Connectivity & Device Pill
            _buildDeviceStatusBar(isOnline, systemStatus),
            const SizedBox(height: 16),

            // Hero: Food Hopper Tank Level Visualizer
            _buildTankVisualizerCard(foodPercent, status?.distanceCm ?? 0.0),
            const SizedBox(height: 16),

            // Live Bowl Weight Scale Card
            _buildBowlWeightCard(bowlWeight, status?.lastFeedTime, status?.lastFeedPortionG ?? 0),
            const SizedBox(height: 20),

            // Fast Feeding Action Center
            _buildFeedActionCenter(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStatusBar(bool isOnline, String systemStatus) {
    Color statusColor = AppTheme.accentGreen;
    if (!isOnline) {
      statusColor = AppTheme.textMuted;
    } else if (systemStatus.contains('KET') || systemStatus.contains('LOI')) {
      statusColor = AppTheme.accentCoral;
    } else if (systemStatus.contains('DANG')) {
      statusColor = AppTheme.accentAmber;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isOnline ? AppTheme.accentGreen : AppTheme.textLight,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isOnline ? 'ESP32 Trực tuyến' : 'ESP32 Ngoại tuyến',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isOnline ? AppTheme.textMain : AppTheme.textMuted,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              systemStatus,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTankVisualizerCard(int percent, double distanceCm) {
    Color levelColor = AppTheme.accentGreen;
    String levelLabel = "Còn đầy hạt";
    if (percent <= 20) {
      levelColor = AppTheme.accentCoral;
      levelLabel = "Sắp hết hạt!";
    } else if (percent <= 45) {
      levelColor = AppTheme.accentAmber;
      levelLabel = "Mức trung bình";
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: AppTheme.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Hộp chứa thức ăn',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                ),
                const Spacer(),
                Text(
                  levelLabel,
                  style: TextStyle(color: levelColor, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                // Tank Gauge Bar
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$percent',
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textMain,
                              letterSpacing: -1,
                            ),
                          ),
                          const Text(
                            '%',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Khoảng cách: ${distanceCm.toStringAsFixed(1)} cm',
                            style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: percent / 100.0,
                          minHeight: 16,
                          backgroundColor: AppTheme.border,
                          valueColor: AlwaysStoppedAnimation<Color>(levelColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Cảm biến siêu âm HC-SR04 đo bề mặt hạt liên tục tại nắp hộp chứa.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBowlWeightCard(double weight, String? lastFeedTime, double lastPortion) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.scale_rounded, color: AppTheme.primary, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Khối lượng tại bát ăn',
                    style: TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        weight.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'gram',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastFeedTime != null
                        ? 'Lần ăn gần nhất: ${lastPortion.toStringAsFixed(0)}g'
                        : 'Chưa có dữ liệu bữa ăn hôm nay',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedActionCenter() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pets_rounded, color: AppTheme.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'Cho thú cưng ăn ngay',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textMain),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_selectedPortion g',
                    style: const TextStyle(
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Chọn nhanh khẩu phần:',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),

            // Chips selector
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetPortions.map((p) {
                final isSelected = _selectedPortion == p;
                return ChoiceChip(
                  label: Text('${p}g'),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) setState(() => _selectedPortion = p);
                  },
                  selectedColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppTheme.textMain,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: AppTheme.background,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: isSelected ? AppTheme.primary : AppTheme.border),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Slider for fine adjustment
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppTheme.primary,
                thumbColor: AppTheme.primary,
                overlayColor: AppTheme.primaryLight,
                valueIndicatorColor: AppTheme.primaryDark,
              ),
              child: Slider(
                value: _selectedPortion.toDouble(),
                min: 10,
                max: 150,
                divisions: 28,
                label: '$_selectedPortion g',
                onChanged: (val) => setState(() => _selectedPortion = val.round()),
              ),
            ),
            const Divider(color: AppTheme.border, height: 24),

            // Override switch (Section 2.3.2)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Chế độ Ghi đè (Override)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textMain),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Bỏ qua bảo vệ chống ăn trùng nếu vừa cho ăn xong.',
                        style: TextStyle(fontSize: 12, color: _isOverride ? AppTheme.accentCoral : AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isOverride,
                  activeTrackColor: AppTheme.accentCoral,
                  onChanged: (val) => setState(() => _isOverride = val),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Big Feed Action Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _handleFeedNow,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.restaurant_rounded),
                label: Text(
                  _isSubmitting
                      ? 'ĐANG GỬI LỆNH...'
                      : _isOverride
                          ? 'GHI ĐÈ & CẤP THỨC ĂN (${_selectedPortion}g)'
                          : 'CẤP THỨC ĂN NGAY (${_selectedPortion}g)',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isOverride ? AppTheme.accentCoral : AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
