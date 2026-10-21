import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:petfeeder_app/services/api_service.dart';
import 'package:petfeeder_app/models/models.dart';
import 'package:petfeeder_app/screens/dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'N24 network failure and app restart resend identical main API command',
    () async {
      final payloads = <String>[];
      final client = MockClient((req) async {
        if (req.url.path == '/api/id') {
          return http.Response(
            jsonEncode({
              'command_id': 'stable-id',
              'now': 1792500000,
              'ttl_s': 60,
            }),
            200,
          );
        }
        if (req.url.path == '/api/feeding/feed') {
          payloads.add(req.body);
          if (payloads.length == 1) throw http.ClientException('Response lost');
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'status': 'SUCCESS'},
              'message': 'Old result',
            }),
            200,
          );
        }
        throw StateError('Unexpected ${req.url}');
      });
      final first = ApiService.testing(client, baseUrl: 'http://test');
      await expectLater(
        first.feedNow(portion: 20),
        throwsA(isA<FeedRequestException>()),
      );
      final reopened = ApiService.testing(client, baseUrl: 'http://test');
      await reopened.feedNow(portion: 80, retry: true);
      expect(payloads.length, 2);
      expect(payloads[1], payloads[0]);
      expect(jsonDecode(payloads[1])['portion'], 20);
    },
  );

  test('N17 null bowl weight stays unknown in main app status', () {
    final device = DeviceStatus.fromJson({
      'online': false,
      'bowl_weight_g': null,
    });
    expect(device.bowlWeightG, isNull);
  });

  test(
    'lost feed response is reconciled without sending another command',
    () async {
      var sends = 0;
      var ids = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/api/id') {
          ids++;
          return http.Response(
            jsonEncode({
              'command_id': 'received-id',
              'now': 1792500000,
              'ttl_s': 60,
            }),
            200,
          );
        }
        if (req.url.path == '/api/feeding/feed') {
          sends++;
          throw http.ClientException('Response lost after server committed');
        }
        if (req.url.path == '/api/commands/received-id') {
          return http.Response(
            jsonEncode({
              'data': {
                'command_id': 'received-id',
                'status': 'DISPENSING',
                'target_portion_g': 30,
                'actual_weight_g': 0,
              },
            }),
            200,
          );
        }
        throw StateError('Unexpected ${req.url}');
      });
      final api = ApiService.testing(client, baseUrl: 'http://test');
      final result = await api.feedNow(portion: 30);
      expect(result['success'], true);
      expect(result['data']['status'], 'DISPENSING');
      expect(result['message'], contains('đang cấp'));
      expect(sends, 1);
      expect(ids, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('pending_feed:http://test')!)['command_id'],
        'received-id',
      );
    },
  );

  test(
    'incompatible ID endpoint fails before submitting or saving a command',
    () async {
      var sends = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/api/id') {
          return http.Response('<html>Not found</html>', 404);
        }
        sends++;
        return http.Response('{}', 200);
      });
      final api = ApiService.testing(client, baseUrl: 'http://test');
      await expectLater(
        api.feedNow(portion: 30),
        throwsA(
          isA<FeedRequestException>()
              .having((e) => e.mayHaveBeenSent, 'may have been sent', false)
              .having((e) => e.message, 'message', contains('Chưa gửi lệnh')),
        ),
      );
      expect(sends, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_feed:http://test'), isNull);
    },
  );

  test(
    'unconfirmed submission retains the exact payload and reports uncertainty',
    () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/id') {
          return http.Response(
            jsonEncode({
              'command_id': 'unconfirmed-id',
              'now': 1792500000,
              'ttl_s': 60,
            }),
            200,
          );
        }
        throw http.ClientException('Connection reset');
      });
      final api = ApiService.testing(client, baseUrl: 'http://test');
      await expectLater(
        api.feedNow(portion: 30),
        throwsA(
          isA<FeedRequestException>()
              .having((e) => e.mayHaveBeenSent, 'may have been sent', true)
              .having((e) => e.message, 'message', contains('Gửi lại cùng mã')),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('pending_feed:http://test')!)['portion'],
        30,
      );
    },
  );

  test('recovered sensor failure never reports a successful meal', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/id') {
        return http.Response(
          jsonEncode({
            'command_id': 'failed-id',
            'now': 1792500000,
            'ttl_s': 60,
          }),
          200,
        );
      }
      if (req.url.path == '/api/commands/failed-id') {
        return http.Response(
          jsonEncode({
            'data': {
              'command_id': 'failed-id',
              'status': 'SENSOR_ERROR',
              'error_code': 'WEIGHT_UNSTABLE',
              'actual_weight_g': null,
            },
          }),
          200,
        );
      }
      throw http.ClientException('Lost feed response');
    });
    final api = ApiService.testing(client, baseUrl: 'http://test');
    final result = await api.feedNow(portion: 30);
    expect(result['success'], false);
    expect(result['code'], 'WEIGHT_UNSTABLE');
    expect(result['data']['actual_weight_g'], isNull);
    expect(result['message'], contains('cân lỗi hoặc bát không còn trên cân'));
  });

  test(
    'validated connection persists and failed candidate never replaces it',
    () async {
      final client = MockClient((req) async => http.Response('{}', 503));
      final api = ApiService.testing(client, baseUrl: 'http://old-server');
      await api.setBaseUrl('http://saved-server:3000/');
      await expectLater(
        api.getDeviceStatus(serverUrl: 'http://unreachable'),
        throwsException,
      );
      expect(api.baseUrl, 'http://saved-server:3000');
      final reopened = ApiService.testing(client, baseUrl: 'http://default');
      await reopened.initialize();
      expect(reopened.baseUrl, 'http://saved-server:3000');
    },
  );

  test(
    'uncertain command cannot be silently resent by a new feed action',
    () async {
      var sends = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/api/id') {
          return http.Response(
            jsonEncode({
              'command_id': 'uncertain-id',
              'now': 1792500000,
              'ttl_s': 60,
            }),
            200,
          );
        }
        if (req.url.path == '/api/commands/uncertain-id') {
          return http.Response('{}', 404);
        }
        if (req.url.path == '/api/feeding/feed') {
          sends++;
          throw http.ClientException('Lost response');
        }
        throw StateError('Unexpected ${req.url}');
      });
      final api = ApiService.testing(client, baseUrl: 'http://test');
      await expectLater(
        api.feedNow(portion: 20),
        throwsA(isA<FeedRequestException>()),
      );
      await expectLater(api.feedNow(portion: 80), throwsStateError);
      expect(sends, 1);
    },
  );

  testWidgets(
    'online missing measurements remain unknown without false empty-food warnings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              status: DeviceStatus.fromJson({
                'online': true,
                'food_level_percent': null,
                'bowl_weight_g': null,
              }),
              isLoading: false,
              onRefresh: () async {},
            ),
          ),
        ),
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Cần thêm hạt'), findsNothing);
      expect(find.text('0.0 g'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Main dashboard disables a new feed when backend/device is offline',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              status: null,
              isLoading: false,
              onRefresh: () async {},
            ),
          ),
        ),
      );
      final button = find.byKey(const ValueKey('feed-now'));
      expect(button, findsOneWidget);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(find.text('—'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
