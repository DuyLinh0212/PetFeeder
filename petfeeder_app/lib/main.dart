import 'dart:async';
import 'package:flutter/material.dart';
import 'models/models.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/schedules_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService().initialize();
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
  Future<void>? _pendingStatus;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchStatus(silent: true),
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
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
      if (mounted) setState(() => _deviceStatus = status);
    } catch (_) {
      if (mounted) setState(() => _deviceStatus = null);
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
      HistoryScreen(onRefresh: _fetchStatus),
      DashboardScreen(
        status: _deviceStatus,
        isLoading: _isLoading,
        onRefresh: _fetchStatus,
      ),
      const SchedulesScreen(),
      SettingsScreen(onRefresh: () => unawaited(_fetchStatus())),
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
