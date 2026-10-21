import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  ApiService({http.Client? client, String? baseUrl})
      : client = client ?? http.Client(),
        baseUrl = baseUrl ?? _defaultUrl();
  static String _defaultUrl() {
    const configured = String.fromEnvironment('API_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb) {
      return Uri.base.port == 8090
          ? Uri.base
              .replace(port: 8080, path: '', query: null, fragment: null)
              .origin
          : Uri.base.origin;
    }
    return 'http://10.0.2.2:8080'; // Android emulator → host PC. Real phone: --dart-define=API_URL=http://PC_LAN_IP:8080
  }

  final http.Client client;
  final String baseUrl;
  static const pendingKey = 'petfeeder.pending.v1';

  Future<dynamic> request(String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl/api/$path');
    final response = await (body == null
            ? client.get(uri)
            : client.post(uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(body)))
        .timeout(const Duration(seconds: 6));
    final dynamic result = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw Exception('${result['error']}: ${result['field'] ?? ''}');
    }
    return result;
  }

  Future<Map<String, dynamic>> state() async =>
      Map<String, dynamic>.from(await request('state'));
  Future<Map<String, dynamic>?> pending() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(pendingKey);
    if (data == null) return null;
    return Map<String, dynamic>.from(jsonDecode(data));
  }

  Future<Map<String, dynamic>> feed(double grams) async {
    final info = await request('id');
    final payload = <String, dynamic>{
      'command_id': info['command_id'],
      'source': 'APP',
      'target_portion_g': grams,
      'override': false,
      'created_at': info['now'],
      'expires_at': info['now'] + info['ttl_s'],
    };
    // Persist the complete original intent BEFORE HTTP. Retry never generates a new ID or expiry.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pendingKey, jsonEncode(payload));
    return Map<String, dynamic>.from(await request('feeding', payload));
  }

  Future<Map<String, dynamic>> retry() async {
    final payload = await pending();
    if (payload == null) throw Exception('Chưa có yêu cầu để gửi lại.');
    return Map<String, dynamic>.from(await request('feeding', payload));
  }

  void dispose() => client.close();
}
