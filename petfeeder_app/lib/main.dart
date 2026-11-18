import 'dart:async';
import 'package:flutter/material.dart';
import 'models/models.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/schedules_screen.dart';
import 'screens/settings_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService().initialize();
  await NotificationService.instance.initialize();
  runApp(const PetFeederApp());
}

class PetFeederApp extends StatelessWidget {
  const PetFeederApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ăng ẳng',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.themeData,
    home: const MainHomeScreen(),
  );
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});
  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 1;
  final _visited = <int>{1};
  DeviceStatus? _deviceStatus;
  bool _isLoading = true;
  bool _realtimeConnected = false;
  bool _freshSnapshotAvailable = false;
  Future<void>? _pendingStatus;
  StreamSubscription<Map<String, dynamic>>? _realtimeSubscription;
  int _connectionRevision = 0;
  int _historyRevision = 0;
  int _scheduleRevision = 0;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _watchRealtime();
  }

  void _watchRealtime() {
    _realtimeSubscription = ApiService().watchRealtime().listen(
      _handleRealtime,
    );
  }

  Future<void> _reconnect() async {
    final revision = ++_connectionRevision;
    await _realtimeSubscription?.cancel();
    await _pendingStatus;
    if (!mounted || revision != _connectionRevision) return;
    setState(() {
      _realtimeConnected = false;
      _freshSnapshotAvailable = false;
      _deviceStatus = null;
    });
    _watchRealtime();
    await _fetchStatus();
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    super.dispose();
  }

  void _handleRealtime(Map<String, dynamic> event) {
    final type = event['type'];
    final data = event['data'];
    if (type == 'realtime_connection') {
      final connected = event['connected'] == true;
      if (mounted) {
        setState(() {
          _realtimeConnected = connected;
          if (connected) {
            _historyRevision++;
            _scheduleRevision++;
          } else {
            _freshSnapshotAvailable = false;
          }
        });
      }
    } else if ((type == 'snapshot' ||
            type == 'device_state' ||
            type == 'snapshot_fallback') &&
        data is Map<String, dynamic>) {
      if (mounted) {
        setState(() {
          _deviceStatus = DeviceStatus.fromJson(data);
          _freshSnapshotAvailable = true;
        });
      }
    } else if (type == 'snapshot_unavailable') {
      if (mounted) setState(() => _freshSnapshotAvailable = false);
    } else if (type == 'feeding_event' || type == 'feeding_command') {
      if (mounted) setState(() => _historyRevision++);
    } else if (type == 'schedules_updated') {
      if (mounted) setState(() => _scheduleRevision++);
    }
  }

  Future<void> _fetchStatus({bool silent = false}) {
    return _pendingStatus ??= _loadStatus(
      silent: silent,
    ).whenComplete(() => _pendingStatus = null);
  }

  Future<void> _loadStatus({required bool silent}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    try {
      final status = await ApiService().getDeviceStatus();
      if (mounted) {
        setState(() {
          _deviceStatus = status;
          _freshSnapshotAvailable = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _deviceStatus = null;
          _freshSnapshotAvailable = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectTab(int index) => setState(() {
    _currentIndex = index;
    _visited.add(index);
  });

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HistoryScreen(onRefresh: _fetchStatus, refreshToken: _historyRevision),
      DashboardScreen(
        status: _deviceStatus,
        isLoading: _isLoading,
        realtimeConnected: _realtimeConnected,
        freshSnapshotAvailable: _freshSnapshotAvailable,
        onRefresh: _fetchStatus,
      ),
      SchedulesScreen(refreshToken: _scheduleRevision),
      SettingsScreen(onRefresh: () => unawaited(_reconnect())),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: _currentIndex == 3
            ? IconButton(
                tooltip: 'Quay lại cho ăn',
                onPressed: () => _selectTab(1),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              )
            : null,
        title: const Text(
          'Ăng ẳng',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          if (_currentIndex != 3)
            IconButton(
              tooltip: 'Cài đặt',
              onPressed: () => setState(() => _currentIndex = 3),
              icon: const Icon(Icons.settings_outlined, size: 25),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _currentIndex,
          children: List.generate(
            screens.length,
            (i) => _visited.contains(i) || i == 3
                ? screens[i]
                : const SizedBox.shrink(),
          ),
        ),
      ),
      bottomNavigationBar: _BottomNavigation(
        selected: _currentIndex,
        onSelected: _selectTab,
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const _BottomNavigation({required this.selected, required this.onSelected});

  Widget _item({
    required int index,
    required String label,
    required IconData icon,
    required IconData activeIcon,
    bool prominent = false,
  }) {
    final active = selected == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => onSelected(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (prominent)
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withAlpha(50),
                          blurRadius: 16,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Icon(activeIcon, color: Colors.white, size: 30),
                  )
                else
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: active
                          ? AppTheme.primaryLight
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      active ? activeIcon : icon,
                      color: active ? AppTheme.primaryDark : AppTheme.textMain,
                      size: 24,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: active ? AppTheme.textMain : AppTheme.textMuted,
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('main-bottom-nav'),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF7698AA).withAlpha(18),
          blurRadius: 22,
          offset: const Offset(0, -5),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _item(
              index: 0,
              label: 'Lịch sử\ncho ăn',
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long_rounded,
            ),
            _item(
              index: 1,
              label: 'Cho ăn',
              icon: Icons.rice_bowl_outlined,
              activeIcon: Icons.rice_bowl_rounded,
              prominent: true,
            ),
            _item(
              index: 2,
              label: 'Kế hoạch\ncho ăn',
              icon: Icons.schedule_outlined,
              activeIcon: Icons.schedule_rounded,
            ),
          ],
        ),
      ),
    ),
  );
}
