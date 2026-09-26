import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiService {
  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // Mặc định: 
  // http://10.0.2.2:3000 khi chạy trên Android Emulator
  // http://localhost:3000 khi chạy trên Windows / Web
  // Có thể đổi thành IP LAN máy tính khi chạy trên điện thoại thật (vd: http://192.168.1.15:3000)
  String baseUrl = 'http://localhost:3000';

  void setBaseUrl(String url) {
    if (url.endsWith('/')) {
      baseUrl = url.substring(0, url.length - 1);
    } else {
      baseUrl = url;
    }
  }

  // 1. Lấy trạng thái thiết bị (FR-05, FR-06)
  Future<DeviceStatus> getDeviceStatus() async {
    final uri = Uri.parse('$baseUrl/api/device/status');
    final res = await http.get(uri).timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return DeviceStatus.fromJson(data['data']);
    } else {
      throw Exception('Lỗi đọc trạng thái: ${res.statusCode}');
    }
  }

  // 2. Kích hoạt lệnh Cho ăn ngay (FR-08)
  Future<Map<String, dynamic>> feedNow({
    required int portion,
    required bool override,
  }) async {
    final uri = Uri.parse('$baseUrl/api/feeding/feed');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'portion': portion,
        'override': override,
      }),
    ).timeout(const Duration(seconds: 5));

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode == 200) {
      return {'success': true, 'message': data['message'] ?? 'Thành công'};
    } else if (res.statusCode == 409) {
      // Bị chặn do ăn trùng (Duplicate feed protection)
      return {
        'success': false,
        'code': 'BLOCKED_DUPLICATE',
        'message': data['message'] ?? 'Lệnh cho ăn bị từ chối do trùng thời gian!',
        'remaining_sec': data['remaining_sec'] ?? 0
      };
    } else {
      return {
        'success': false,
        'code': data['code'] ?? 'ERROR',
        'message': data['message'] ?? 'Lỗi khi gửi lệnh cho ăn (${res.statusCode})'
      };
    }
  }

  // 3. Quản lý lịch (FR-01, FR-02)
  Future<List<FeedingSchedule>> getSchedules() async {
    final uri = Uri.parse('$baseUrl/api/schedules');
    final res = await http.get(uri).timeout(const Duration(seconds: 4));
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
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'time': time,
        'portion_g': portionG,
        'days': days,
        'enabled': enabled,
      }),
    );
    if (res.statusCode == 201) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return FeedingSchedule.fromJson(data['data']);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    throw Exception(data['message'] ?? 'Lỗi tạo lịch');
  }

  Future<FeedingSchedule> toggleSchedule(String id) async {
    final uri = Uri.parse('$baseUrl/api/schedules/$id/toggle');
    final res = await http.patch(uri);
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return FeedingSchedule.fromJson(data['data']);
    }
    throw Exception('Lỗi chuyển trạng thái lịch');
  }

  Future<bool> deleteSchedule(String id) async {
    final uri = Uri.parse('$baseUrl/api/schedules/$id');
    final res = await http.delete(uri);
    return res.statusCode == 200;
  }

  // 4. Lịch sử cho ăn (FR-10)
  Future<List<FeedingRecord>> getHistory({int limit = 40}) async {
    final uri = Uri.parse('$baseUrl/api/feeding/history?limit=$limit');
    final res = await http.get(uri).timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final List list = data['data'] ?? [];
      return list.map((item) => FeedingRecord.fromJson(item)).toList();
    }
    throw Exception('Lỗi tải lịch sử');
  }

  Future<bool> clearHistory() async {
    final uri = Uri.parse('$baseUrl/api/feeding/history');
    final res = await http.delete(uri);
    return res.statusCode == 200;
  }

  // 5. Cảnh báo & Thông báo (FR-07)
  Future<List<AlertNotification>> getNotifications() async {
    final uri = Uri.parse('$baseUrl/api/notifications');
    final res = await http.get(uri).timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final List list = data['data'] ?? [];
      return list.map((item) => AlertNotification.fromJson(item)).toList();
    }
    throw Exception('Lỗi tải thông báo');
  }

  Future<bool> markNotificationRead(String id) async {
    final uri = Uri.parse('$baseUrl/api/notifications/$id/read');
    final res = await http.patch(uri);
    return res.statusCode == 200;
  }

  Future<bool> clearNotifications() async {
    final uri = Uri.parse('$baseUrl/api/notifications');
    final res = await http.delete(uri);
    return res.statusCode == 200;
  }
}
