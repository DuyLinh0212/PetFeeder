import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';

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

  // 1. Lấy trạng thái thiết bị (FR-05, FR-06)
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

  // 2. Kích hoạt lệnh Cho ăn ngay (FR-08)
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

  Future<Map<String, dynamic>> feedNow({
    required num portion,
    required bool override,
    bool retry = false,
    String? retryOf,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'pending_feed:$baseUrl';
    final saved = prefs.getString(key);
    Map<String, dynamic>? command = saved == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(saved));
    if (retry && command == null) {
      throw Exception('Chưa có yêu cầu đã lưu để gửi lại.');
    }
    if (!retry && command != null) {
      final res = await _get(
        Uri.parse('$baseUrl/api/history'),
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) {
        throw Exception(
          'Chưa xác định kết quả yêu cầu trước; dùng Gửi lại cùng mã.',
        );
      }
      final rows = jsonDecode(utf8.decode(res.bodyBytes))['commands'] as List;
      final previous = rows
          .where((r) => r['command_id'] == command!['command_id'])
          .firstOrNull;
      const terminal = {
        'SUCCESS',
        'PARTIAL',
        'OVER_PORTION',
        'REJECTED',
        'COMMAND_EXPIRED',
        'SENSOR_ERROR',
        'JAM_ERROR',
        'TIMEOUT',
        'FOOD_EMPTY',
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
      final res = await _get(
        Uri.parse('$baseUrl/api/id'),
      ).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) throw Exception('Không tạo được mã yêu cầu');
      final id = jsonDecode(utf8.decode(res.bodyBytes));
      command = {
        'command_id': id['command_id'],
        'created_at': id['now'],
        'expires_at': id['now'] + id['ttl_s'],
        'portion': portion,
        'override': override,
        'retry_of': ?retryOf,
      };
      if (!await prefs.setString(key, jsonEncode(command))) {
        throw Exception('Không lưu được mã; chưa gửi lệnh.');
      }
    }
    final res = await _post(
      Uri.parse('$baseUrl/api/feeding/feed'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(command),
    ).timeout(const Duration(seconds: 5));
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode == 400 && data['code'] != 'COMMAND_ID_CONFLICT') {
      await prefs.remove(key);
    }
    return {
      'success': res.statusCode == 200 && data['success'] == true,
      'code': data['code'],
      'message': data['message'] ?? 'Chờ xác nhận thiết bị',
      'data': data['data'],
    };
  }

  // 3. Quản lý lịch (FR-01, FR-02)
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

  // 4. Lịch sử cho ăn (FR-10)
  Future<List<FeedingRecord>> getHistory({int limit = 40}) async {
    final uri = Uri.parse('$baseUrl/api/feeding/history?limit=$limit');
    final res = await _get(uri).timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final List list = data['data'] ?? [];
      return list.map((item) => FeedingRecord.fromJson(item)).toList();
    }
    throw Exception('Lỗi tải lịch sử');
  }

  Future<bool> clearHistory() async {
    final uri = Uri.parse('$baseUrl/api/feeding/history');
    final res = await _delete(uri).timeout(const Duration(seconds: 8));
    return res.statusCode == 200;
  }

  // 5. Cảnh báo & Thông báo (FR-07)
  Future<List<AlertNotification>> getNotifications() async {
    final uri = Uri.parse('$baseUrl/api/notifications');
    final res = await _get(uri).timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final List list = data['data'] ?? [];
      return list.map((item) => AlertNotification.fromJson(item)).toList();
    }
    throw Exception('Lỗi tải thông báo');
  }

  Future<bool> markNotificationRead(String id) async {
    final uri = Uri.parse('$baseUrl/api/notifications/$id/read');
    final res = await _patch(uri).timeout(const Duration(seconds: 8));
    return res.statusCode == 200;
  }

  Future<bool> clearNotifications() async {
    final uri = Uri.parse('$baseUrl/api/notifications');
    final res = await _delete(uri).timeout(const Duration(seconds: 8));
    return res.statusCode == 200;
  }
}
