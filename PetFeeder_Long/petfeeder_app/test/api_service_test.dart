import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:petfeeder_long/services/api_service.dart';
import 'package:petfeeder_long/screens/dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'N24 timeout + app service restart retry preserves ID, portion and original expiry',
      () async {
    Map<String, dynamic>? original;
    final first = ApiService(client: MockClient((request) async {
      if (request.url.path.endsWith('/id')) {
        return http.Response(
            jsonEncode(
                {'command_id': 'stable-id', 'now': 1800000000, 'ttl_s': 60}),
            200);
      }
      original = Map<String, dynamic>.from(jsonDecode(request.body));
      throw TimeoutException(
          'response lost after device could receive command');
    }));
    await expectLater(first.feed(20), throwsA(isA<TimeoutException>()));
    first.dispose();
    Map<String, dynamic>? replay;
    final second = ApiService(client: MockClient((request) async {
      replay = Map<String, dynamic>.from(jsonDecode(request.body));
      return http.Response(
          jsonEncode({'status': 'SUCCESS', 'actual_weight_g': 20}), 200);
    }));
    final result = await second.retry();
    expect(replay, equals(original));
    expect(replay!['expires_at'], 1800000060);
    expect(result['status'], 'SUCCESS');
    second.dispose();
  });

  testWidgets(
      'Dashboard renders unknown weight and never labels ACCEPTED as SUCCESS',
      (tester) async {
    final api = ApiService(
        client: MockClient((request) async => http.Response(
            jsonEncode({
              'mode': 'DEMO',
              'connection': 'ONLINE',
              'device': {'weight_g': null},
              'commands': [],
              'events': [],
              'schedules': [],
              'config': {
                'food_label': '',
                'food_confirmed': false,
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
            }),
            200)));
    await tester.pumpWidget(MaterialApp(home: DashboardScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa xác định'), findsOneWidget);
    expect(find.byKey(const Key('feed-new')), findsOneWidget);
    expect(find.text('Đã cho ăn thành công'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
