import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

// One session shared by Dashboard and History. Polling never sends a feeding command.
class FeedingSession extends ChangeNotifier {
  String? id;
  Map<String, dynamic>? result;
  bool pending = false, posting = false, checking = false;
  String? problem;
  Timer? _timer;
  int _polls = 0;
  bool _disposed = false;
  bool get paused => result?['status'] == 'PAUSED';
  String get label {
    if (problem != null) return problem!;
    final status = result?['status'];
    if (status == 'SUCCESS') return 'Đã cấp ${result?['actual_weight_g']} g.';
    if (status == 'PAUSED') {
      return 'Đã dừng servo. Đặt lại bát và kiểm tra phiên trong Nhật ký.';
    }
    if (pending) {
      return status == 'DISPENSING'
          ? 'Thiết bị đang cấp hạt…'
          : 'Đang chờ kết quả từ thiết bị…';
    }
    return 'Phiên $status · ${result?['error_code'] ?? 'Chưa có kết quả'}';
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> send({
    required int portion,
    bool override = false,
    String? retryOf,
    bool confirmBowl = false,
  }) async {
    final resume = paused && retryOf == id;
    if ((pending && !resume) || posting) {
      return {
        'success': false,
        'code': 'DEVICE_BUSY',
        'message': 'Đang có phiên cần kiểm tra.',
      };
    }
    final previousId = id, previousResult = result;
    id =
        'app_${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32).toRadixString(16)}';
    posting = pending = true;
    result = null;
    problem = null;
    _polls = 0;
    _changed();
    try {
      final response = await ApiService().feedNow(
        portion: portion,
        override: override,
        commandId: id!,
        retryOf: retryOf,
        confirmBowl: confirmBowl,
      );
      if (_disposed) return response;
      if (response['success'] == true) {
        result = response['data'] as Map<String, dynamic>?;
        _consume();
        _schedule();
      } else {
        pending = resume;
        id = resume ? previousId : null;
        result = resume ? previousResult : null;
      }
      return response;
    } catch (_) {
      problem =
          'Chưa xác nhận được lệnh. Kiểm tra lại; không gửi thêm khẩu phần.';
      return {'success': true, 'message': problem};
    } finally {
      posting = false;
      _changed();
    }
  }

  void _consume() {
    final status = result?['status'];
    pending =
        [
          'PUBLISHING',
          'ACCEPTED',
          'DISPENSING',
          'PAUSED',
          'UNKNOWN',
        ].contains(status) ||
        status == null;
    if (!pending) _timer?.cancel();
  }

  void _schedule() {
    _timer?.cancel();
    if (pending && !paused && _polls < 30 && !_disposed) {
      _timer = Timer(const Duration(seconds: 1), check);
    }
  }

  Future<void> check() async {
    if (id == null || checking || _disposed) return;
    checking = true;
    _changed();
    try {
      final data = await ApiService().getCommand(id!);
      if (_disposed) return;
      result = data;
      problem = null;
      _consume();
    } catch (_) {
      problem = 'Chưa đọc được kết quả. Nhấn Kiểm tra lại.';
    } finally {
      checking = false;
      _polls++;
      _changed();
      _schedule();
    }
  }

  Future<void> recover(String commandId) async {
    if (id != null || _disposed) return;
    id = commandId;
    pending = true;
    _changed();
    await check();
  }

  Future<void> cancel() async {
    if (id == null || checking) return;
    try {
      await ApiService().cancelCommand(id!);
      await check();
    } catch (_) {
      problem = 'Chưa xác nhận hủy. Hãy kiểm tra lại.';
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
