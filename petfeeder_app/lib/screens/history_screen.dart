import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<FeedingRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final list = await ApiService().getHistory();
      setState(() => _records = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải nhật ký: $e'), backgroundColor: AppTheme.accentCoral),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleClearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa nhật ký'),
        content: const Text('Bạn có muốn xóa toàn bộ lịch sử các lần cho ăn không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa hết', style: TextStyle(color: AppTheme.accentCoral)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService().clearHistory();
      _loadHistory();
    }
  }

  Widget _buildSourceIcon(String source) {
    IconData icon;
    Color bg;
    Color iconColor;

    switch (source.toLowerCase()) {
      case 'app':
        icon = Icons.phone_android_rounded;
        bg = AppTheme.primaryLight;
        iconColor = AppTheme.primaryDark;
        break;
      case 'schedule':
        icon = Icons.alarm_rounded;
        bg = const Color(0xFFE0F2FE);
        iconColor = const Color(0xFF0284C7);
        break;
      case 'button':
        icon = Icons.touch_app_rounded;
        bg = const Color(0xFFFEF3C7);
        iconColor = const Color(0xFFD97706);
        break;
      case 'override':
        icon = Icons.flash_on_rounded;
        bg = const Color(0xFFFFE4E6);
        iconColor = const Color(0xFFE11D48);
        break;
      default:
        icon = Icons.pets_rounded;
        bg = AppTheme.background;
        iconColor = AppTheme.textMuted;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: iconColor, size: 22),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color text;
    String label;

    switch (status.toUpperCase()) {
      case 'SUCCESS':
      case 'HOAN TAT':
        bg = AppTheme.accentGreen.withAlpha(30);
        text = AppTheme.accentGreen;
        label = 'Thành công';
        break;
      case 'JAM_ERROR':
        bg = AppTheme.accentCoral.withAlpha(30);
        text = AppTheme.accentCoral;
        label = 'Kẹt thức ăn';
        break;
      case 'EMPTY':
        bg = AppTheme.accentCoral.withAlpha(30);
        text = AppTheme.accentCoral;
        label = 'Hết hạt';
        break;
      case 'BLOCKED':
        bg = AppTheme.accentAmber.withAlpha(30);
        text = AppTheme.accentAmber;
        label = 'Bị chặn';
        break;
      default:
        bg = AppTheme.border;
        text = AppTheme.textMuted;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        label,
        style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  String _formatDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('HH:mm - dd/MM/yyyy').format(dt);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhật ký cho ăn'),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Xóa lịch sử',
              onPressed: _handleClearHistory,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: _records.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_rounded, size: 64, color: AppTheme.textLight),
                          const SizedBox(height: 12),
                          const Text('Chưa có lịch sử bữa ăn nào', style: TextStyle(color: AppTheme.textMuted)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _records.length,
                      separatorBuilder: (ctx, idx) => const SizedBox(height: 12),
                      itemBuilder: (ctx, idx) {
                        final r = _records[idx];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                _buildSourceIcon(r.triggerSource),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            _formatDateTime(r.timestamp),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                          const Spacer(),
                                          _buildStatusBadge(r.status),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        r.message.isNotEmpty
                                            ? r.message
                                            : 'Nguồn lệnh: ${r.triggerSource.toUpperCase()}',
                                        style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Khối lượng: ${r.actualWeightG.toStringAsFixed(1)}g / ${r.targetPortionG}g',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textMain,
                                        ),
                                      ),
                                    ],
                                  ),
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
