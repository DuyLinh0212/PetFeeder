import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:petfeeder_long/screens/dashboard_screen.dart';
import 'package:petfeeder_long/services/api_service.dart';

Map<String, dynamic> state() => {
      'mode': 'DEMO',
      'connection': 'ONLINE',
      'device': {'weight_g': 0, 'occurred_at': 1800000000},
      'commands': [],
      'events': [],
      'schedules': [],
      'daily': {'actual_dispensed_g': 0, 'confirmed_sessions': 0},
      'config': {
        'food_label': 'Hạt demo',
        'food_confirmed': true,
        'require_pet': false,
        'max_portion_g': 100,
        'daily_limit_g': 200,
        'min_interval_s': 180,
        'observation_s': 60,
        'food_stale_s': 3600,
        'command_ttl_s': 60,
        'feed_timeout_s': 30,
        'tolerance_g': 2,
        'timezone_offset_min': 420
      }
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      '320px phone with larger text: navigation, settings and schedule sheet do not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiService(
        client: MockClient((_) async => http.Response(jsonEncode(state()), 200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!),
        home: DashboardScreen(api: api)));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('mobile-shell'))).width, 320);
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.textContaining('command_id'), findsNothing);
    expect(find.text('Thức ăn trong hộp'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Lịch ăn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm lịch cho ăn'));
    await tester.pumpAndSettle();
    expect(find.text('Lưu lịch'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('Lưu lịch'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cài đặt'));
    await tester.pumpAndSettle();
    expect(find.text('Thức ăn trong hộp'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets(
      'Backend fails after loading: stale online badge is removed and feeding is disabled',
      (tester) async {
    bool fail = false;
    final api = ApiService(client: MockClient((_) async {
      if (fail) throw Exception('network');
      return http.Response(jsonEncode(state()), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    await tester.pumpWidget(MaterialApp(home: DashboardScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Đã kết nối'), findsOneWidget);
    fail = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Đã kết nối'), findsNothing);
    expect(find.text('Mất kết nối'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('feed-new')))
            .onPressed,
        isNull);
    expect(
        find.textContaining('Đang hiển thị dữ liệu lần cuối'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
