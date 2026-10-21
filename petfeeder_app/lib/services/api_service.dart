import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
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

  // Trạng thái cân, giới hạn ngày và kết nối thiết bị.
  Future<DeviceStatus> getDeviceStatus({String? serverUrl}) async {
    final uri = Uri.parse('${serverUrl ?? baseUrl}/api/device/status');
    final res = await _get(uri).timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return DeviceStatus.fromJson(data['data']);
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

  String? _visionAddress;
  Future<Map<String, dynamic>> _visionPost(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    Future<http.Response> send(String address) => _post(
      Uri.parse('$address/api/vision/$path'),
      headers: headers,
      body: body,
    ).timeout(const Duration(seconds: 10));
    var response = await send(_visionAddress ?? baseUrl);
    if (response.statusCode == 404 &&
        _configuredUrl.isNotEmpty &&
        _configuredUrl != baseUrl) {
      response = await send(_configuredUrl);
      if (response.statusCode == 200) _visionAddress = _configuredUrl;
    }
    final result = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      throw Exception(result['message'] ?? 'Không kết nối được YOLO');
    }
    return Map<String, dynamic>.from(result['data']);
  }

  Future<String> startVision() async =>
      (await _visionPost('start'))['session'] as String;
  Future<void> stopVision(String session) async {
    await _visionPost('stop', headers: {'X-Camera-Session': session});
  }

  Future<Map<String, dynamic>> detectCameraFrame(
    List<int> bytes,
    String session,
  ) => _visionPost(
    'detect',
    headers: {
      'Content-Type': 'application/octet-stream',
      'X-Camera-Session': session,
    },
    body: bytes,
  );

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

  Future<Map<String, dynamic>> feedNow({
    required num portion,
    bool retry = false,
  }) async {
    final server = baseUrl;
    var stage = 'đọc yêu cầu đã lưu';
    var submitted = false;
    Map<String, dynamic>? command;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'pending_feed:$server';
      final saved = prefs.getString(key);
      command = saved == null ? null : _feedBody(saved);
      if (retry && command == null) {
        throw StateError('Chưa có yêu cầu đã lưu để gửi lại.');
      }
      if (!retry && command != null) {
        stage = 'đọc kết quả yêu cầu trước';
        final res = await _get(
          Uri.parse('$server/api/commands/${Uri.encodeComponent(command['command_id'] as String)}'),
        ).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200 && res.statusCode != 404) {
          throw FeedRequestException(
            'Không đọc được kết quả yêu cầu trước (HTTP ${res.statusCode}). Giữ nguyên mã lệnh và thử lại khi kết nối hoạt động.',
            mayHaveBeenSent: false,
          );
        }
        final previous = res.statusCode == 200
            ? Map<String, dynamic>.from(
                _feedBody(utf8.decode(res.bodyBytes))['data'] as Map,
              )
            : null;
        const terminal = {
          'SUCCESS',
          'PARTIAL',
          'OVER_PORTION',
          'REJECTED',
          'COMMAND_EXPIRED',
          'SENSOR_ERROR',
          'BOWL_MISSING',
          'TIMEOUT',
          'INTERRUPTED',
        };
        if (previous != null && terminal.contains(previous['status'])) {
          command = null;
        }
        if (command != null) {
          throw StateError(
            'Chưa rõ kết quả yêu cầu trước. Dùng Gửi lại cùng mã.',
          );
        }
        // A new command is allowed only after the previous result is terminal.
      }
      if (command == null) {
        stage = 'tạo mã yêu cầu';
        final res = await _get(
          Uri.parse('$server/api/id'),
        ).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) {
          throw FeedRequestException(
            'Không tạo được mã yêu cầu trên máy chủ (HTTP ${res.statusCode}). Chưa gửi lệnh cho ăn; kiểm tra địa chỉ và phiên bản backend.',
            mayHaveBeenSent: false,
          );
        }
        final id = _feedBody(utf8.decode(res.bodyBytes));
        if (id['command_id'] is! String ||
            (id['command_id'] as String).isEmpty ||
            id['now'] is! int ||
            id['ttl_s'] is! int) {
          throw const FormatException('Invalid command ID response');
        }
        command = {
          'command_id': id['command_id'],
          'created_at': id['now'],
          'expires_at': id['now'] + id['ttl_s'],
          'portion': portion,
        };
        stage = 'lưu mã yêu cầu trên điện thoại';
        if (!await prefs.setString(key, jsonEncode(command))) {
          throw StateError(
            'Không lưu được mã trên điện thoại. Chưa gửi lệnh cho ăn.',
          );
        }
      }
      stage = 'gửi lệnh cho ăn';
      submitted = true;
      final res = await _post(
        Uri.parse('$server/api/feeding/feed'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(command),
      ).timeout(const Duration(seconds: 5));
      final data = _feedBody(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200 && data['success'] is! bool) {
        throw const FormatException('Invalid feeding response');
      }
      final returned = data['data'] is Map
          ? Map<String, dynamic>.from(data['data'] as Map)
          : const <String, dynamic>{};
      const terminal = {
        'SUCCESS', 'PARTIAL', 'OVER_PORTION', 'REJECTED',
        'COMMAND_EXPIRED', 'SENSOR_ERROR', 'BOWL_MISSING', 'TIMEOUT', 'INTERRUPTED',
      };
      if (res.statusCode == 400 && data['code'] == 'COMMAND_EXPIRED') {
        await prefs.remove(key);
      }
      if (data['code'] != 'COMMAND_ID_CONFLICT' &&
          terminal.contains(returned['status'])) {
        await prefs.remove(key);
      }
      return {
        'success': res.statusCode == 200 && data['success'] == true,
        'code': data['code'],
        'message': data['message'] ?? 'Chờ xác nhận thiết bị',
        'data': data['data'],
      };
    } on StateError {
      rethrow;
    } on FeedRequestException {
      rethrow;
    } catch (error) {
      debugPrint('PetFeeder: lỗi khi $stage: $error');
      final submittedId = command?['command_id'];
      if (submitted && submittedId is String) {
        // Query only: a lost HTTP response must never cause another feed POST.
        final recovered = await _recoverFeed(server, submittedId);
        if (recovered != null) return recovered;
      }
      final reason = error is TimeoutException
          ? 'Máy chủ phản hồi quá chậm khi $stage.'
          : error is http.ClientException
          ? 'Mất kết nối với máy chủ khi $stage.'
          : error is FormatException
          ? 'Dữ liệu không hợp lệ khi $stage. Kiểm tra phiên bản app và backend.'
          : 'Không thể $stage.';
      throw FeedRequestException(
        '$reason ${submitted ? 'Chưa rõ lệnh đã tới thiết bị. Dùng Gửi lại cùng mã để tra kết quả.' : 'Chưa gửi lệnh cho ăn mới.'}',
        mayHaveBeenSent: submitted,
      );
    }
  }

  Map<String, dynamic> _feedBody(String body) {
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object');
    }
    return value;
  }

  Future<Map<String, dynamic>?> _recoverFeed(
    String server,
    String commandId,
  ) async {
    try {
      final res = await _get(
        Uri.parse('$server/api/commands/${Uri.encodeComponent(commandId)}'),
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final previous = Map<String, dynamic>.from(
        _feedBody(utf8.decode(res.bodyBytes))['data'] as Map,
      );
      final status = previous['status'];
      final message = switch (status) {
        'QUEUED' => 'Máy chủ đã nhận yêu cầu; đang chờ thiết bị xác nhận.',
        'ACCEPTED' => 'Thiết bị đã nhận yêu cầu; đang chuẩn bị cấp thức ăn.',
        'DISPENSING' => 'Thiết bị đang cấp khẩu phần đã yêu cầu.',
        'SUCCESS' => 'Thiết bị đã xác nhận hoàn tất phiên cấp.',
        'DELIVERY_UNKNOWN' =>
          'Máy chủ đã nhận yêu cầu nhưng chưa có kết quả từ thiết bị. Dùng Gửi lại cùng mã.',
        'COMMAND_EXPIRED' =>
          'Yêu cầu đã hết hạn; thiết bị không thực hiện lệnh này.',
        'SENSOR_ERROR' =>
          'Thiết bị đã dừng vì cân lỗi hoặc bát không còn trên cân.',
        'BOWL_MISSING' =>
          'Bát đã rời cân giữa phiên. Lượng cấp chưa xác định; cần kiểm tra và đối soát thiết bị.',
        'REJECTED' => 'Thiết bị từ chối yêu cầu: ${previous['error_code'] ?? 'REJECTED'}.',
        'PARTIAL' => 'Thiết bị đã dừng trước khi đạt đủ lượng đặt.',
        'TIMEOUT' => 'Thiết bị đã dừng sau khi hết thời gian cấp tối đa.',
        'INTERRUPTED' => 'Phiên cấp bị gián đoạn; cần kiểm tra thiết bị.',
        'OVER_PORTION' => 'Thiết bị đã dừng để tránh cấp quá lượng đặt.',
        _ => null,
      };
      if (message == null) return null;
      const terminal = {
        'SUCCESS', 'PARTIAL', 'OVER_PORTION', 'REJECTED',
        'COMMAND_EXPIRED', 'SENSOR_ERROR', 'BOWL_MISSING', 'TIMEOUT', 'INTERRUPTED',
      };
      if (terminal.contains(status)) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pending_feed:$server');
      }
      return {
        'success': const {
          'QUEUED',
          'ACCEPTED',
          'DISPENSING',
          'SUCCESS',
          'DELIVERY_UNKNOWN',
        }.contains(status),
        'code': status == 'DELIVERY_UNKNOWN'
            ? 'AWAITING_DEVICE_RESULT'
            : previous['error_code'],
        'message': message,
        'data': Map<String, dynamic>.from(previous),
      };
    } catch (_) {
      // Keep the saved payload when both the reply and the lookup are unavailable.
      return null;
    }
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
