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
    'network failure does not pin the next feed request to an old command',
    () async {
      final payloads = <Map<String, dynamic>>[];
      var ids = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/api/id') {
          ids++;
          return http.Response(
            jsonEncode({
              'command_id': 'fresh-id-$ids',
              'now': 1792500000,
              'ttl_s': 60,
            }),
            200,
          );
        }
        if (req.url.path == '/api/feeding/feed') {
          payloads.add(Map<String, dynamic>.from(jsonDecode(req.body) as Map));
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
        if (req.url.path == '/api/commands/fresh-id-1') {
          return http.Response('{}', 404);
        }
        throw StateError('Unexpected ${req.url}');
      });
      final first = ApiService.testing(client, baseUrl: 'http://test');
      await expectLater(
        first.feedNow(portion: 20),
        throwsA(isA<FeedRequestException>()),
      );
      final reopened = ApiService.testing(client, baseUrl: 'http://test');
      await reopened.feedNow(portion: 80);
      expect(payloads.length, 2);
      expect(payloads[0]['command_id'], 'fresh-id-1');
      expect(payloads[1]['command_id'], 'fresh-id-2');
      expect(payloads[0]['portion'], 20);
      expect(payloads[1]['portion'], 80);
    },
  );

  test('N17 null bowl weight stays unknown in main app status', () {
    final device = DeviceStatus.fromJson({
      'online': false,
      'bowl_weight_g': null,
    });
    expect(device.bowlWeightG, isNull);
  });

  test('lost feed response leaves no saved lock or same-ID lookup', () async {
    var sends = 0;
    var ids = 0;
    var lookups = 0;
    final client = MockClient((req) async {
      if (req.url.path == '/api/id') {
        ids++;
        return http.Response(
          jsonEncode({
            'command_id': 'received-id-$ids',
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
      if (req.url.path.startsWith('/api/commands/')) lookups++;
      throw StateError('Unexpected ${req.url}');
    });
    final api = ApiService.testing(client, baseUrl: 'http://test');
    await expectLater(
      api.feedNow(portion: 30),
      throwsA(
        isA<FeedRequestException>()
            .having((e) => e.mayHaveBeenSent, 'may have been sent', true)
            .having(
              (e) => e.message,
              'message',
              contains('không lưu lệnh chờ'),
            ),
      ),
    );
    expect(sends, 1);
    expect(ids, 1);
    expect(lookups, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pending_feed:http://test'), isNull);
  });

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
    'unconfirmed submission reports uncertainty without saving a retry payload',
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
              .having((e) => e.message, 'message', contains('không lưu lệnh chờ')),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_feed:http://test'), isNull);
    },
  );

  test('sensor failure response never reports a successful meal', () async {
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
      if (req.url.path == '/api/feeding/feed') {
        return http.Response(
          jsonEncode({
            'success': false,
            'code': 'WEIGHT_UNSTABLE',
            'message': 'Cân chưa ổn định trong thời hạn cho phép.',
            'data': {
              'command_id': 'failed-id',
              'status': 'SENSOR_ERROR',
              'error_code': 'WEIGHT_UNSTABLE',
              'actual_weight_g': null,
            },
          }),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      throw StateError('Unexpected ${req.url}');
    });
    final api = ApiService.testing(client, baseUrl: 'http://test');
    final result = await api.feedNow(portion: 30);
    expect(result['success'], false);
    expect(result['code'], 'WEIGHT_UNSTABLE');
    expect(result['data']['actual_weight_g'], isNull);
    expect(result['message'], contains('Cân chưa ổn định'));
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
    'a new feed action creates a new command after an uncertain response',
    () async {
      var sends = 0;
      var ids = 0;
      final submittedIds = <String>[];
      final client = MockClient((req) async {
        if (req.url.path == '/api/id') {
          ids++;
          return http.Response(
            jsonEncode({
              'command_id': 'uncertain-id-$ids',
              'now': 1792500000,
              'ttl_s': 60,
            }),
            200,
          );
        }
        if (req.url.path.startsWith('/api/commands/uncertain-id-')) {
          return http.Response('{}', 404);
        }
        if (req.url.path == '/api/feeding/feed') {
          sends++;
          submittedIds.add(jsonDecode(req.body)['command_id'] as String);
          throw http.ClientException('Lost response');
        }
        throw StateError('Unexpected ${req.url}');
      });
      final api = ApiService.testing(client, baseUrl: 'http://test');
      await expectLater(
        api.feedNow(portion: 20),
        throwsA(isA<FeedRequestException>()),
      );
      await expectLater(
        api.feedNow(portion: 80),
        throwsA(isA<FeedRequestException>()),
      );
      expect(sends, 2);
      expect(ids, 2);
      expect(submittedIds, ['uncertain-id-1', 'uncertain-id-2']);
    },
  );

  testWidgets(
    'online missing bowl and hopper measurements remain unknown',
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
      expect(find.text('—'), findsNWidgets(2));
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
      expect(find.text('—'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
