import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

class FeedRequestException implements Exception {
  final String message;
  final bool mayHaveBeenSent;
  const FeedRequestException(this.message, {required this.mayHaveBeenSent});

  @override
  String toString() => message;
}

class ApiService {
  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();
  ApiService.testing(this._client, {required this.baseUrl});
  http.Client? _client;
  Future<http.Response> _get(Uri uri) => _client?.get(uri) ?? http.get(uri);
  Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _client?.post(uri, headers: headers, body: body) ??
      http.post(uri, headers: headers, body: body);
  Future<http.Response> _postFeed(Uri uri, {required String body}) async {
    final requestClient = _client ?? http.Client();
    try {
      return await requestClient
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 2));
    } finally {
      // Closing the request-scoped client aborts the socket when the timeout fires.
      if (_client == null) requestClient.close();
    }
  }

  Future<http.Response> _put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _client?.put(uri, headers: headers, body: body) ??
      http.put(uri, headers: headers, body: body);
  Future<http.Response> _patch(Uri uri) =>
      _client?.patch(uri) ?? http.patch(uri);
  Future<http.Response> _delete(Uri uri) =>
      _client?.delete(uri) ?? http.delete(uri);
  Future<http.Response> _deleteJson(Uri uri, {required String body}) =>
      _client?.delete(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ) ??
      http.delete(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

  // Mặc định:
  // http://10.0.2.2:3000 khi chạy trên Android Emulator
  // http://localhost:3000 khi chạy trên Windows / Web
  // Có thể đổi thành IP LAN máy tính khi chạy trên điện thoại thật (vd: http://192.168.1.15:3000)
  static const _configuredUrl = String.fromEnvironment('API_URL');
  String baseUrl = _configuredUrl.isNotEmpty
      ? _configuredUrl
      : kIsWeb || defaultTargetPlatform != TargetPlatform.android
      ? 'http://localhost:3000'
      : 'http://10.0.2.2:3000';

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('main_api_base_url') ?? baseUrl;
    await prefs.remove('pending_feed:$baseUrl');
  }

  Future<void> setBaseUrl(String url) async {
    final candidate = url.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('Địa chỉ máy chủ không hợp lệ.');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('main_api_base_url', candidate)) {
      throw StateError('Chưa lưu được địa chỉ kết nối.');
    }
    baseUrl = candidate;
  }

  Future<void> saveConnectionAddress(
    String address, {
    String? serverUrl,
  }) async {
    final endpoint = serverUrl ?? baseUrl;
    final response = await _put(
      Uri.parse('$endpoint/api/device/connection'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'connection_address': address}),
    ).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(
        body['message'] ?? 'Không lưu được địa chỉ kết nối lên máy chủ.',
      );
    }
  }

  Future<bool> registerNotificationFid({
    required String fid,
    required String installationId,
    required String platform,
  }) async {
    final response = await _post(
      Uri.parse('$baseUrl/api/notifications/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fid': fid,
        'installation_id': installationId,
        'platform': platform,
      }),
    ).timeout(const Duration(seconds: 8));
    final data = _feedBody(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Không đăng ký được thông báo.');
    }
    final result = data['data'];
    return result is Map && result['push_enabled'] == true;
  }

  Future<void> unregisterNotificationFid({
    required String fid,
    required String installationId,
    required String platform,
  }) async {
    final response = await _deleteJson(
      Uri.parse('$baseUrl/api/notifications/register'),
      body: jsonEncode({
        'fid': fid,
        'installation_id': installationId,
        'platform': platform,
      }),
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('Không gỡ được đăng ký thông báo khỏi máy chủ.');
    }
  }

  Stream<Map<String, dynamic>> watchRealtime() {
    late final StreamController<Map<String, dynamic>> controller;
    final cancelled = Completer<void>();
    var retrySeconds = 1;
    var stopped = false;
    WebSocketChannel? channel;
    Timer? readyTimer;
    Timer? retryTimer;

    void emit(Map<String, dynamic> event) {
      if (!stopped && controller.hasListener && !controller.isClosed) {
        controller.add(event);
      }
    }

    Future<void> waitForReady(Future<void> ready) async {
      final timeout = Completer<void>();
      readyTimer = Timer(const Duration(seconds: 5), () {
        if (!timeout.isCompleted) {
          timeout.completeError(
            TimeoutException('WebSocket connection timed out'),
          );
        }
      });
      try {
        await Future.any<void>([ready, timeout.future, cancelled.future]);
      } finally {
        readyTimer?.cancel();
        readyTimer = null;
      }
    }

    Future<void> waitForRetry() async {
      final delay = Completer<void>();
      retryTimer = Timer(Duration(seconds: retrySeconds), delay.complete);
      try {
        await Future.any<void>([delay.future, cancelled.future]);
      } finally {
        retryTimer?.cancel();
        retryTimer = null;
      }
    }

    Future<void> run() async {
      while (!stopped) {
        WebSocketChannel? current;
        try {
          final base = Uri.parse(baseUrl);
          final uri = base.replace(
            scheme: base.scheme == 'https' ? 'wss' : 'ws',
            path: '/api/realtime',
            query: null,
            fragment: null,
          );
          current = WebSocketChannel.connect(uri);
          channel = current;
          await waitForReady(current.ready);
          if (stopped) break;
          retrySeconds = 1;
          emit({'type': 'realtime_connection', 'connected': true});
          await for (final frame in current.stream) {
            if (stopped) break;
            try {
              final decoded = jsonDecode(frame.toString());
              if (decoded is Map<String, dynamic>) emit(decoded);
            } catch (_) {
              // Ignore malformed frames and keep the live connection.
            }
          }
        } catch (error) {
          if (!stopped) {
            debugPrint('PetFeeder: WebSocket disconnected: $error');
          }
        } finally {
          readyTimer?.cancel();
          readyTimer = null;
          try {
            await current?.sink.close();
          } catch (_) {}
          if (identical(channel, current)) channel = null;
        }

        if (stopped) break;
        emit({'type': 'realtime_connection', 'connected': false});
        try {
          emit({
            'type': 'snapshot_fallback',
            'data': await _getDeviceStatusJson(),
          });
        } catch (error) {
          if (!stopped) {
            debugPrint('PetFeeder: snapshot fallback failed: $error');
          }
          emit({'type': 'snapshot_unavailable'});
        }
        if (stopped) break;
        await waitForRetry();
        retrySeconds = (retrySeconds * 2).clamp(1, 15).toInt();
      }
      if (!stopped && !controller.isClosed) await controller.close();
    }

    controller = StreamController<Map<String, dynamic>>(
      onListen: () => unawaited(run()),
      onCancel: () async {
        stopped = true;
        if (!cancelled.isCompleted) cancelled.complete();
        readyTimer?.cancel();
        retryTimer?.cancel();
        try {
          await channel?.sink.close();
        } catch (_) {}
      },
    );
    return controller.stream;
  }

  // Trạng thái cân, giới hạn ngày và kết nối thiết bị.
  Future<DeviceStatus> getDeviceStatus({String? serverUrl}) async {
    return DeviceStatus.fromJson(
      await _getDeviceStatusJson(serverUrl: serverUrl),
    );
  }

  Future<Map<String, dynamic>> _getDeviceStatusJson({String? serverUrl}) async {
    final uri = Uri.parse('${serverUrl ?? baseUrl}/api/device/status');
    final res = await _get(uri).timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is Map<String, dynamic> && data['data'] is Map) {
        return Map<String, dynamic>.from(data['data'] as Map);
      }
      throw const FormatException('Invalid device status response');
    } else {
      throw Exception('Lỗi đọc trạng thái: ${res.statusCode}');
    }
  }

  // Đọc và cập nhật chính sách cấp thức ăn.
  Future<Map<String, dynamic>> getSafetyConfig() async {
    final res = await _get(
      Uri.parse('$baseUrl/api/device/config'),
    ).timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) throw Exception('Không đọc được cấu hình');
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(res.bodyBytes))['data'],
    );
  }

  Future<void> saveSafetyConfig(Map<String, dynamic> patch) async {
    final res = await _put(
      Uri.parse('$baseUrl/api/device/config'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(patch),
    ).timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) {
      throw Exception(jsonDecode(utf8.decode(res.bodyBytes))['message']);
    }
  }

  Future<Map<String, dynamic>> feedNow({required num portion}) async {
    final server = baseUrl;
    var stage = 'tạo mã yêu cầu';
    var submitted = false;
    try {
      final idResponse = await _get(
        Uri.parse('$server/api/id'),
      ).timeout(const Duration(seconds: 2));
      if (idResponse.statusCode != 200) {
        throw FeedRequestException(
          'Không tạo được mã yêu cầu trên máy chủ (HTTP ${idResponse.statusCode}). Chưa gửi lệnh cho ăn; kiểm tra địa chỉ và phiên bản backend.',
          mayHaveBeenSent: false,
        );
      }
      final id = _feedBody(utf8.decode(idResponse.bodyBytes));
      if (id['command_id'] is! String ||
          (id['command_id'] as String).isEmpty ||
          id['now'] is! int ||
          id['ttl_s'] is! int) {
        throw const FormatException('Invalid command ID response');
      }
      final commandId = id['command_id'] as String;
      final command = {
        'command_id': commandId,
        'created_at': id['now'],
        'expires_at': id['now'] + id['ttl_s'],
        'portion': portion,
      };

      stage = 'gửi lệnh cho ăn';
      submitted = true;
      final response = await _postFeed(
        Uri.parse('$server/api/feeding/feed'),
        body: jsonEncode(command),
      );
      final data = _feedBody(utf8.decode(response.bodyBytes));
      if (data['success'] is! bool) {
        throw const FormatException('Invalid feeding response');
      }
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'code': data['code'],
        'message': data['message'] ?? 'Chờ xác nhận thiết bị',
        'data': data['data'],
      };
    } on FeedRequestException {
      rethrow;
    } catch (error) {
      debugPrint('PetFeeder: lỗi khi $stage: $error');
      final reason = error is TimeoutException
          ? 'Máy chủ phản hồi quá chậm khi $stage.'
          : error is http.ClientException
          ? 'Mất kết nối với máy chủ khi $stage.'
          : error is FormatException
          ? 'Dữ liệu không hợp lệ khi $stage. Kiểm tra phiên bản app và backend.'
          : 'Không thể $stage.';
      throw FeedRequestException(
        '$reason ${submitted ? 'Lệnh có thể đã tới thiết bị. Ứng dụng không lưu lệnh chờ; hãy kiểm tra trạng thái thiết bị trước khi quyết định cấp tiếp.' : 'Chưa gửi lệnh cho ăn.'}',
        mayHaveBeenSent: submitted,
      );
    }
  }

  Future<Map<String, dynamic>> retryInterruptedFeed({
    required String commandId,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/api/feeding/recovery/${Uri.encodeComponent(commandId)}/retry',
    );
    final response = await _post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(const <String, dynamic>{}),
    ).timeout(const Duration(seconds: 8));
    final data = _feedBody(utf8.decode(response.bodyBytes));
    if (response.statusCode == 200 && data['success'] == true) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    throw Exception(data['message'] ?? 'Chưa thể cấp lại phần còn thiếu.');
  }

  Map<String, dynamic> _feedBody(String body) {
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object');
    }
    return value;
  }

  // Lịch được lưu trên ESP32 để tiếp tục chạy khi mất mạng.
  Future<List<FeedingSchedule>> getSchedules() async {
    final uri = Uri.parse('$baseUrl/api/schedules');
    final res = await _get(uri).timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final List list = data['data'] ?? [];
      return list.map((item) => FeedingSchedule.fromJson(item)).toList();
    }
    throw Exception('Lỗi tải danh sách lịch: ${res.statusCode}');
  }

  Future<List<FeedingRecord>> getFeedingHistory({int limit = 50}) async {
    final uri = Uri.parse('$baseUrl/api/feeding/history?limit=$limit');
    final res = await _get(uri).timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) {
      throw Exception('Lỗi tải lịch sử cho ăn: ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final List records = data['data']?['records'] ?? const [];
    return records
        .map((row) => FeedingRecord.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<FeedingSchedule> createSchedule({
    required String name,
    required String time,
    required int portionG,
    required List<String> days,
    required bool enabled,
  }) async {
    final uri = Uri.parse('$baseUrl/api/schedules');
    final res = await _post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'time': time,
        'portion_g': portionG,
        'days': days,
        'enabled': enabled,
      }),
    ).timeout(const Duration(seconds: 8));
    if (res.statusCode == 201) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return FeedingSchedule.fromJson(data['data']);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    throw Exception(data['message'] ?? 'Lỗi tạo lịch');
  }

  Future<FeedingSchedule> toggleSchedule(String id) async {
    final uri = Uri.parse('$baseUrl/api/schedules/$id/toggle');
    final res = await _patch(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return FeedingSchedule.fromJson(data['data']);
    }
    throw Exception('Lỗi chuyển trạng thái lịch');
  }

  Future<bool> deleteSchedule(String id) async {
    final uri = Uri.parse('$baseUrl/api/schedules/$id');
    final res = await _delete(uri).timeout(const Duration(seconds: 8));
    return res.statusCode == 200;
  }
}
