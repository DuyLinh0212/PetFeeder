import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:petfeeder_app/screens/camera_demo_screen.dart';
import 'package:petfeeder_app/services/api_service.dart';

void main() {
  test(
    'Visible web camera survives switching focus to Wokwi, but hidden camera stops',
    () {
      expect(
        shouldStopCameraForLifecycle(AppLifecycleState.inactive, web: true),
        isFalse,
      );
      expect(
        shouldStopCameraForLifecycle(AppLifecycleState.resumed, web: true),
        isFalse,
      );
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        expect(shouldStopCameraForLifecycle(state, web: true), isTrue);
      }
      expect(
        shouldStopCameraForLifecycle(AppLifecycleState.inactive, web: false),
        isTrue,
      );
    },
  );
  testWidgets(
    'Camera is opt-in; denial sends no frames and manual controls are absent',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var opens = 0;
      final results = <Map<String, dynamic>>[];
      final api = ApiService.testing(
        MockClient((req) async {
          throw StateError('Unexpected ${req.url}');
        }),
        baseUrl: 'http://test',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CameraDemoScreen(
            api: api,
            cameraProvider: () async {
              opens++;
              throw CameraException('CameraAccessDenied', 'Denied by user');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(opens, 0);
      expect(find.textContaining('Giả lập'), findsNothing);
      await tester.ensureVisible(find.text('Mở camera thật'));
      await tester.tap(find.text('Mở camera thật'));
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(results, isEmpty);
      await tester.ensureVisible(find.textContaining('Không mở được camera:'));
      expect(find.textContaining('Không mở được camera:'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
