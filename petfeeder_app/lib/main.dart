import 'dart:async';
import 'package:flutter/material.dart';
import 'models/models.dart';
import 'services/api_service.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/schedules_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';

void main() => runApp(const PetFeederApp());

class PetFeederApp extends StatelessWidget {
  const PetFeederApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PetFeeder',
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
  int _currentIndex = 0;
  final _visited = <int>{0};
  DeviceStatus? _deviceStatus;
  bool _isLoading = true;
  Future<void>? _pendingStatus;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 3),
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

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      DashboardScreen(
        status: _deviceStatus,
        isLoading: _isLoading,
        onRefresh: _fetchStatus,
      ),
      const SchedulesScreen(),
      const HistoryScreen(),
      SettingsScreen(onRefresh: _fetchStatus),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.pets_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'petfeeder',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới trạng thái thiết bị',
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.surface,
              foregroundColor: AppTheme.primary,
            ),
            onPressed: _isLoading ? null : _fetchStatus,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _currentIndex,
          children: List.generate(
            screens.length,
            (i) => _visited.contains(i) ? screens[i] : const SizedBox.shrink(),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withAlpha(12),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) => setState(() {
              _currentIndex = i;
              _visited.add(i);
            }),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                selectedIcon: Icon(Icons.space_dashboard_rounded),
                label: 'Tổng quan',
              ),
              NavigationDestination(
                icon: Icon(Icons.schedule_outlined),
                selectedIcon: Icon(Icons.schedule_rounded),
                label: 'Lịch ăn',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_rounded),
                label: 'Nhật ký',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_rounded),
                label: 'Cài đặt',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
