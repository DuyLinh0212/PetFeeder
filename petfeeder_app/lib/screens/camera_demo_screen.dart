import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/api_service.dart';
import '../widgets/app_components.dart';

bool shouldStopCameraForLifecycle(
  AppLifecycleState state, {
  required bool web,
}) =>
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.hidden ||
    state == AppLifecycleState.detached ||
    (!web && state == AppLifecycleState.inactive);

class CameraDemoScreen extends StatefulWidget {
  final ApiService? api;
  final Future<List<CameraDescription>> Function()? cameraProvider;
  const CameraDemoScreen({super.key, this.api, this.cameraProvider});
  @override
  State<CameraDemoScreen> createState() => _CameraDemoScreenState();
}

class _CameraDemoScreenState extends State<CameraDemoScreen>
    with WidgetsBindingObserver {
  ApiService get api => widget.api ?? ApiService();
  CameraController? camera;
  Timer? visionTimer;
  bool detecting = false;
  String visionLabel = 'Chưa có ảnh để nhận diện';
  bool starting = false, feeding = false, hasPet = false;
  int generation = 0;
  String? session;
  String message =
      'Mở camera để YOLO tự phát hiện chó/mèo. Không cần chọn kết quả bằng tay.';
  bool get live => camera?.value.isInitialized == true && !starting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> openCamera() async {
    final ticket = ++generation;
    setState(() {
      starting = true;
      hasPet = false;
    });
    CameraController? next;
    try {
      final cameras = await (widget.cameraProvider ?? availableCameras)();
      if (cameras.isEmpty) {
        throw StateError('Không tìm thấy camera.');
      }
      next = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await next.initialize().timeout(const Duration(seconds: 25));
      if (!mounted || ticket != generation) {
        await next.dispose();
        return;
      }
      final token = await api.startVision();
      if (!mounted || ticket != generation) {
        await api.stopVision(token);
        await next.dispose();
        return;
      }
      setState(() {
        camera = next;
        session = token;
        starting = false;
        message =
            'YOLO đang xử lý ảnh thật. Cần 2 khung hình liên tiếp có chó/mèo để cho qua kiểm tra hiện diện.';
      });
      unawaited(detectFrame());
      visionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(detectFrame());
      });
    } catch (e) {
      await next?.dispose();
      if (ticket != generation) {
        return;
      }
      if (mounted && ticket == generation) {
        setState(() {
          starting = false;
          message =
              'Không mở được camera: $e. Trên Web cần localhost/HTTPS và bạn cho phép camera.';
        });
      }
    }
  }

  Future<void> detectFrame() async {
    if (!live || detecting || session == null) return;
    final ticket = generation;
    final current = camera!;
    final started = DateTime.now();
    detecting = true;
    try {
      final picture = await current.takePicture().timeout(
        const Duration(seconds: 5),
      );
      final result = await api.detectCameraFrame(
        await picture.readAsBytes(),
        session!,
      );
      if (!mounted || ticket != generation) return;
      final boxes = (result['detections'] as List).cast<Map<String, dynamic>>();
      setState(() {
        hasPet = result['presence_verified'] == true;
        if (DateTime.now().difference(started).inSeconds >= 3) {
          visionLabel = 'Ảnh xử lý quá chậm — chờ khung hình mới';
        } else if (boxes.isEmpty) {
          visionLabel = 'Không phát hiện chó hoặc mèo';
        } else {
          visionLabel = boxes
              .map((b) {
                final name = b['label'] == 'cat' ? 'Mèo' : 'Chó';
                final score = ((b['confidence'] as num) * 100).toStringAsFixed(
                  1,
                );
                return '$name · $score%';
              })
              .join(' / ');
        }
      });
    } catch (error) {
      if (mounted && ticket == generation) {
        setState(() {
          hasPet = false;
          visionLabel = 'Chưa nhận diện được';
          message = 'Lỗi nhận diện: $error';
        });
      }
    } finally {
      detecting = false;
    }
  }

  Future<void> stopCamera({bool redraw = true}) async {
    generation++;
    visionTimer?.cancel();
    visionTimer = null;
    final old = camera;
    camera = null;
    starting = false;
    hasPet = false;
    final oldSession = session;
    session = null;
    if (oldSession != null) {
      unawaited(api.stopVision(oldSession).catchError((Object _) {}));
    }
    if (redraw && mounted) {
      setState(() {
        visionLabel = 'Camera đã tắt — không có kết quả hiện tại';
      });
    }
    await old?.dispose();
  }

  Future<void> feed({bool retry = false}) async {
    setState(() => feeding = true);
    try {
      final response = await api.feedNow(
        portion: 20,
        override: false,
        retry: retry,
      );
      if (mounted) {
        setState(() {
          message =
              '${response['data']?['status'] ?? response['code'] ?? ''}: ${response['message']}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => message = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => feeding = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Web inactive only means focus moved to Wokwi/another window. Keep the
    // visible camera and its verification alive until hidden or explicitly stopped.
    if (shouldStopCameraForLifecycle(state, web: kIsWeb) &&
        (state != AppLifecycleState.inactive || camera != null) &&
        (camera != null || starting)) {
      unawaited(stopCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stopCamera(redraw: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Camera · YOLO chó/mèo')),
    body: PageContent(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'NHẬN DIỆN CHÓ / MÈO BẰNG YOLO11n',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Camera gửi khung ảnh đến YOLO trên laptop để nhận diện chó/mèo thật. AI phân biệt loài, chưa xác minh được đúng con thú đã đăng ký. Ảnh chụp mèo cũng có thể được nhận là mèo.',
          ),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: camera?.value.isInitialized == true
                ? camera!.value.aspectRatio
                : 4 / 3,
            child: live
                ? CameraPreview(camera!)
                : ColoredBox(
                    color: Colors.black12,
                    child: Center(
                      child: Text(
                        starting ? 'Đang mở camera...' : 'Camera đang tắt',
                      ),
                    ),
                  ),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: live || starting ? null : openCamera,
                child: const Text('Mở camera thật'),
              ),
              TextButton(
                onPressed: live || starting ? () => stopCamera() : null,
                child: const Text('Tắt camera'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            visionLabel,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            hasPet
                ? 'Đã phát hiện chó/mèo từ 2 ảnh liên tiếp'
                : 'Chưa đủ điều kiện hiện diện — chờ ảnh mới',
          ),
          const Text(
            'Ngưỡng AI 50%. Kết quả hết hạn sau tối đa 5 giây; mất thú, tắt camera hoặc lỗi YOLO sẽ chặn lệnh mới. Nhận diện loài, chưa xác minh từng cá thể.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: !live || !hasPet || feeding ? null : () => feed(),
            child: Text(feeding ? 'Đang gửi...' : 'Cho ăn · 20 g'),
          ),
          TextButton(
            onPressed: feeding ? null : () => feed(retry: true),
            child: const Text('Gửi lại cùng mã'),
          ),
          const Text(
            'Phát hiện chó/mèo chỉ cho qua bước hiện diện. Vẫn cần chủ xác nhận thức ăn, đủ thời gian chờ, cân hợp lệ và hạn mức. Xem kết quả ở Nhật ký hoặc Serial.',
          ),
          const SizedBox(height: 12),
          Text(message),
        ],
      ),
    ),
  );
}
