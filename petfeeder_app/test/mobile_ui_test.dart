import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:petfeeder_app/main.dart';
import 'package:petfeeder_app/services/api_service.dart';

class FakeBackend {
  bool online = true;
  bool failLists = false;
  bool empty = false;
  bool duplicate = false;
  bool failDelete = false;
  bool failCandidate = false;
  bool failId = false;
  bool partial = false;
  Completer<void>? pendingFeed;
  final requests = <http.Request>[];
  final schedule = <String, dynamic>{
    'id': 'breakfast',
    'name': 'Bữa sáng cho bé',
    'time': '07:00',
    'portion_g': 35,
    'days': ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'],
    'enabled': true,
  };

  http.Response response(dynamic data, {int code = 200}) => http.Response(
    jsonEncode({
      'success': code < 400,
      'data': data,
      'message': 'Đã nhận yêu cầu; chờ thiết bị xác nhận.',
    }),
    code,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> handle(http.Request req) async {
    requests.add(req);
    final path = req.url.path;
    if (failCandidate && req.url.host == 'unreachable.local') {
      return response(null, code: 503);
    }
    if (path == '/api/device/status') {
      return response({
        'online': online,
        'system_status': 'SAN SANG',
        'food_level_percent': 76,
        'bowl_weight_g': 24.5,
        'last_feed_time': '2026-10-21T00:00:00Z',
        'last_feed_portion_g': 35,
      });
    }
    if (path == '/api/id') {
      if (failId) return http.Response('<html>Not found</html>', 404);
      return http.Response(
        jsonEncode({
          'command_id': 'test-${requests.length}',
          'now': 1792500000,
          'ttl_s': 60,
        }),
        200,
      );
    }
    if (path == '/api/history') {
      return http.Response(jsonEncode({'commands': []}), 200);
    }
    if (path == '/api/device/config') {
      return response({
        'food_confirmed': false,
        'food_label': '',
        'require_pet': false,
        'max_portion_g': 100,
        'daily_limit_g': 200,
        'min_interval_s': 180,
        'observation_s': 60,
        'food_stale_s': 3600,
        'feed_timeout_s': 30,
        'max_daily_feeds': 6,
        'bowl_capacity_g': 150,
        'max_feed_pulses': 15,
      });
    }
    if (req.method == 'DELETE') {
      return response(null, code: failDelete ? 500 : 200);
    }
    if (path == '/api/feeding/feed') {
      if (pendingFeed != null) await pendingFeed!.future;
      if (duplicate && jsonDecode(req.body)['override'] == false) {
        return http.Response(
          jsonEncode({
            'code': 'BLOCKED_DUPLICATE',
            'message': 'Bé vừa ăn. Vui lòng đợi hết khoảng chờ bảo vệ.',
            'remaining_sec': 120,
          }),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return response(null);
    }
    if (req.method == 'POST' && path == '/api/schedules') {
      return response({
        'id': 'new-meal',
        ...jsonDecode(req.body) as Map<String, dynamic>,
      }, code: 201);
    }
    if (req.method == 'PATCH') {
      schedule['enabled'] = !(schedule['enabled'] as bool);
      return response(schedule);
    }
    if (failLists) return response(null, code: 503);
    if (empty) return response([]);
    if (path == '/api/schedules') return response([schedule]);
    if (path == '/api/feeding/history') {
      return response([
        {
          'id': 'meal',
          'timestamp': '2026-10-21T00:00:00Z',
          'trigger_source': 'schedule',
          'target_portion_g': 35,
          'actual_weight_g': partial ? 8.0 : 34.8,
          'status': partial ? 'JAM_ERROR' : 'SUCCESS',
          'message': 'Bữa sáng đã được cấp đúng lịch cho bé.',
        },
      ]);
    }
    if (path == '/api/notifications') {
      return response([
        {
          'id': 'alert',
          'title': 'Nhắc kiểm tra hộp hạt',
          'message': 'Vệ sinh hộp hạt định kỳ để thức ăn luôn khô và sạch.',
          'level': 'info',
          'read': false,
        },
      ]);
    }
    return response(null, code: 404);
  }
}

const previewKey = ValueKey('preview');

Future<void> start(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await ApiService().setBaseUrl('http://localhost:3000');
  addTearDown(() => ApiService().setBaseUrl('http://localhost:3000'));
  await tester.pumpWidget(
    RepaintBoundary(
      key: previewKey,
      child: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: const PetFeederApp(),
      ),
    ),
  );
  // MaterialApp installs a view MediaQuery. Override its accessibility scale.
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpAndSettle();
}

Future<void> navigate(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: find.byType(Scrollable).hitTestable().first,
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['PETFEEDER_PREVIEW_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(previewKey),
    );
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    // Pin real font metrics across Windows and Linux; recent SDKs need not ship Roboto.
    final configFile = File('.dart_tool/package_config.json').absolute;
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final flutter = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((package) => package['name'] == 'flutter');
    final sdk = Directory.fromUri(
      configFile.uri.resolve(flutter['rootUri'] as String),
    ).parent.parent.path;
    final fonts = '$sdk/bin/cache/artifacts/material_fonts';
    final font =
        Platform.environment['PETFEEDER_PREVIEW_FONT'] ??
        'test/fonts/Roboto-Regular.ttf';
    final loader = FontLoader('Roboto')
      ..addFont(
        Future.value(ByteData.sublistView(await File(font).readAsBytes())),
      );
    await loader.load();
    final iconFile = Directory(fonts).listSync().whereType<File>().firstWhere(
      (file) =>
          file.uri.pathSegments.last.toLowerCase() ==
          'materialicons-regular.otf',
    );
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(ByteData.sublistView(await iconFile.readAsBytes())),
      );
    await icons.load();
  });

  for (final config in [
    (const Size(320, 740), 1.0),
    (const Size(320, 740), 2.0),
    (const Size(390, 844), 1.4),
    (const Size(768, 1024), 2.0),
  ]) {
    testWidgets(
      'all screens fit ${config.$1.width}px at text scale ${config.$2}',
      (tester) {
        final api = FakeBackend();
        api.schedule['name'] =
            'Bữa sáng đặc biệt dành cho thú cưng của gia đình';
        return http.runWithClient(() async {
          await start(tester, size: config.$1, scale: config.$2);
          for (final tab in ['Tổng quan', 'Lịch ăn', 'Nhật ký', 'Cài đặt']) {
            await navigate(tester, tab);
            expect(tester.takeException(), isNull);
            for (var i = 0; i < 5; i++) {
              await tester.drag(
                find.byType(ListView).hitTestable().first,
                const Offset(0, -350),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }, () => MockClient(api.handle));
      },
    );
  }

  testWidgets('feeding action is visible on the initial phone viewport', (
    tester,
  ) {
    final api = FakeBackend();
    return http.runWithClient(() async {
      await start(tester);
      expect(find.text('Cho ăn · 30 g').hitTestable(), findsOneWidget);
      final button = tester.getRect(find.byKey(const ValueKey('feed-now')));
      expect(
        button.bottom,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(NavigationBar)).dy),
      );
      expect(find.text('76%').hitTestable(), findsOneWidget);
      expect(find.text('24.5 g').hitTestable(), findsOneWidget);
      expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient(api.handle));
  });

  testWidgets('four tab previews and feeding controls retain their state', (
    tester,
  ) {
    final api = FakeBackend();
    return http.runWithClient(() async {
      await start(tester);
      await capture(tester, 'dashboard');
      await reveal(tester, find.text('Cho ăn · 30 g'));
      await tester.tap(find.widgetWithText(ChoiceChip, '60 g'));
      await tester.pumpAndSettle();
      await capture(tester, 'feeding');
      await navigate(tester, 'Lịch ăn');
      await capture(tester, 'schedules');
      await tester.tap(find.text('Thêm lịch ăn'));
      await tester.pumpAndSettle();
      await capture(tester, 'schedule-editor');
      Navigator.of(tester.element(find.text('Lưu lịch ăn'))).pop();
      await tester.pumpAndSettle();
      await navigate(tester, 'Nhật ký');
      await capture(tester, 'history');
      await navigate(tester, 'Cài đặt');
      await capture(tester, 'settings');
      await navigate(tester, 'Tổng quan');
      expect(find.text('Cho ăn · 60 g'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient(api.handle));
  });

  testWidgets('offline telemetry is unknown and feeding is disabled', (tester) {
    final api = FakeBackend()..online = false;
    return http.runWithClient(() async {
      await start(tester);
      expect(find.text('76%'), findsNothing);
      expect(find.text('Cần thêm hạt'), findsNothing);
      await reveal(tester, find.text('Cho ăn · 30 g'));
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('feed-now')),
      );
      expect(button.onPressed, isNull);
      expect(api.requests.where((r) => r.method == 'POST'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient(api.handle));
  });

  testWidgets(
    'safety limits expand and save without overflow on a narrow screen with large text',
    (tester) {
      final api = FakeBackend();
      return http.runWithClient(() async {
        await start(tester, size: const Size(320, 740), scale: 2);
        await navigate(tester, 'Cài đặt');
        await reveal(tester, find.text('Giới hạn và thời gian kiểm thử'));
        await tester.tap(find.text('Giới hạn và thời gian kiểm thử'));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Lưu xác nhận và giới hạn'));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Lưu xác nhận và giới hạn'));
        await tester.pumpAndSettle();
        final saved = api.requests
            .where(
              (r) => r.method == 'PUT' && r.url.path == '/api/device/config',
            )
            .toList();
        expect(saved, hasLength(1));
        final patch = jsonDecode(saved.single.body);
        expect(patch['min_interval_s'], 180);
        expect(patch['max_daily_feeds'], 6);
        expect(patch['bowl_capacity_g'], 150);
        expect(patch['max_feed_pulses'], 15);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient(api.handle));
    },
  );

  testWidgets(
    'partial recovery confirms and sends only the missing grams with the parent ID',
    (tester) {
      final api = FakeBackend()..partial = true;
      return http.runWithClient(() async {
        await start(tester);
        await navigate(tester, 'Nhật ký');
        await reveal(tester, find.text('Cấp phần còn thiếu'));
        await tester.tap(find.text('Cấp phần còn thiếu'));
        await tester.pumpAndSettle();
        expect(
          api.requests.where((r) => r.url.path == '/api/feeding/feed'),
          isEmpty,
        );
        await tester.tap(find.text('Gửi yêu cầu'));
        await tester.pumpAndSettle();
        final sent = api.requests
            .where((r) => r.url.path == '/api/feeding/feed')
            .toList();
        expect(sent, hasLength(1));
        final command = jsonDecode(sent.single.body);
        expect(command['portion'], 27);
        expect(command['retry_of'], 'meal');
        expect(command['override'], false);
        expect(command['command_id'], isNotEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient(api.handle));
    },
  );

  testWidgets('feeding reports preflight failure while device remains online', (
    tester,
  ) {
    final api = FakeBackend()..failId = true;
    return http.runWithClient(() async {
      await start(tester);
      await reveal(tester, find.text('Cho ăn · 30 g'));
      await tester.tap(find.text('Cho ăn · 30 g'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Không tạo được mã yêu cầu'), findsOneWidget);
      expect(find.text('Đang trực tuyến'), findsOneWidget);
      expect(
        api.requests.where((r) => r.url.path == '/api/feeding/feed'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient(api.handle));
  });

  testWidgets('duplicate warning enforces cooldown and blocks double taps', (
    tester,
  ) {
    final api = FakeBackend()..duplicate = true;
    return http.runWithClient(() async {
      await start(tester);
      final feed = find.text('Cho ăn · 30 g');
      await reveal(tester, feed);
      api.pendingFeed = Completer<void>();
      await tester.tap(feed);
      await tester.pump();
      final pending = tester.widget<FilledButton>(
        find.byKey(const ValueKey('feed-now')),
      );
      expect(pending.onPressed, isNull);
      expect(
        api.requests.where((r) => r.url.path == '/api/feeding/feed').length,
        1,
      );
      api.pendingFeed!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Bữa ăn vừa được cấp'), findsOneWidget);
      expect(find.text('Vẫn cho ăn'), findsNothing);
      expect(
        find.text('Vui lòng đợi hết khoảng chờ bảo vệ rồi mới cho ăn tiếp.'),
        findsOneWidget,
      );
      final sent = api.requests
          .where((r) => r.url.path == '/api/feeding/feed')
          .map((r) => jsonDecode(r.body)['override'])
          .toList();
      expect(sent, [false]);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient(api.handle));
  });

  testWidgets(
    'schedule editor handles keyboard and submits selected days once',
    (tester) {
      final api = FakeBackend();
      return http.runWithClient(() async {
        await start(tester, size: const Size(320, 740), scale: 1.4);
        await navigate(tester, 'Lịch ăn');
        await reveal(tester, find.text('Thêm lịch ăn'));
        await tester.tap(find.text('Thêm lịch ăn'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Bữa tối');
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await reveal(tester, find.widgetWithText(FilterChip, 'CN'));
        await tester.tap(find.widgetWithText(FilterChip, 'CN'));
        await reveal(tester, find.text('Lưu lịch ăn'));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Lưu lịch ăn'));
        await tester.pumpAndSettle();
        final sent = api.requests
            .where((r) => r.url.path == '/api/schedules' && r.method == 'POST')
            .toList();
        expect(sent, hasLength(1));
        expect(jsonDecode(sent.single.body)['days'], [
          'T2',
          'T3',
          'T4',
          'T5',
          'T6',
          'T7',
        ]);
        expect(jsonDecode(sent.single.body)['portion_g'], 35);
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient(api.handle));
    },
  );

  testWidgets('failed lists show retry instead of an empty success state', (
    tester,
  ) {
    final api = FakeBackend()..failLists = true;
    return http.runWithClient(() async {
      await start(tester);
      await navigate(tester, 'Lịch ăn');
      expect(find.text('Chưa tải được lịch ăn'), findsOneWidget);
      api.failLists = false;
      api.empty = true;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.text('Bữa ăn đầu tiên đang chờ'), findsOneWidget);
      api.failLists = true;
      await navigate(tester, 'Nhật ký');
      expect(find.text('Chưa tải được nhật ký'), findsOneWidget);
      await navigate(tester, 'Cài đặt');
      await reveal(tester, find.text('Chưa tải được thông báo'));
      expect(find.text('Chưa có cảnh báo'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient(api.handle));
  });

  testWidgets(
    'failed deletion keeps schedule and failed candidate keeps API URL',
    (tester) {
      final api = FakeBackend()
        ..failDelete = true
        ..failCandidate = true;
      return http.runWithClient(() async {
        await start(tester);
        await navigate(tester, 'Lịch ăn');
        await tester.tap(find.byTooltip('Xóa lịch Bữa sáng cho bé'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Xóa lịch'));
        await tester.pumpAndSettle();
        expect(find.text('Bữa sáng cho bé'), findsOneWidget);
        await navigate(tester, 'Cài đặt');
        await tester.enterText(find.byType(TextFormField), 'unreachable.local');
        await reveal(tester, find.text('Lưu kết nối'));
        await tester.tap(find.text('Lưu kết nối'));
        await tester.pumpAndSettle();
        expect(
          find.text('Nhập địa chỉ http:// hoặc https:// hợp lệ.'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byType(TextFormField),
          'http://unreachable.local:3000',
        );
        await tester.tap(find.text('Lưu kết nối'));
        await tester.pumpAndSettle();
        expect(ApiService().baseUrl, 'http://localhost:3000');
        expect(
          find.text(
            'Không kết nối được. Kiểm tra địa chỉ và mạng Wi-Fi rồi thử lại.',
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }, () => MockClient(api.handle));
    },
  );
}
