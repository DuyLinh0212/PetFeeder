class DeviceStatus {
  final String deviceId;
  final bool online;
  final String systemStatus;
  final int? foodLevelPercent;
  final double? distanceCm;
  final double? bowlWeightG;
  final String ipAddress;
  final int wifiRssi;
  final String? lastSeen;
  final String? lastFeedTime;
  final double? lastFeedPortionG;
  final String lastFeedStatus;
  final bool mqttConnected;
  final int safeIntervalSec;
  final bool scaleValid,
      ultrasonicValid,
      busy,
      lockdown,
      hopperVerified,
      presenceAvailable,
      bowlPresent;
  final bool simulationMode;
  final int contractVersion;
  final String? activeCommandId;
  String? get feedBlockReason {
    if (!online) return 'Kết nối thiết bị để cho bé ăn từ xa.';
    if (contractVersion != 2) return 'Cần cập nhật firmware để cấp hạt.';
    if (busy) return 'Đang có phiên cho ăn. Xem trạng thái hoặc Nhật ký.';
    if (lockdown) return 'Thiết bị đang khóa an toàn. Kiểm tra trong Cài đặt.';
    if (!hopperVerified) return 'Kiểm tra và xác nhận hộp hạt trong Cài đặt.';
    if (!scaleValid || !ultrasonicValid) {
      return 'Cảm biến chưa có số đo hợp lệ.';
    }
    if (!presenceAvailable) {
      return 'Thiếu cảm biến hiện diện bát. Kiểm tra Cài đặt.';
    }
    if (!bowlPresent) return 'Hãy đặt lại bát thức ăn.';
    return null;
  }

  DeviceStatus({
    required this.deviceId,
    required this.online,
    required this.systemStatus,
    required this.foodLevelPercent,
    required this.distanceCm,
    required this.bowlWeightG,
    required this.ipAddress,
    required this.wifiRssi,
    this.lastSeen,
    this.lastFeedTime,
    required this.lastFeedPortionG,
    required this.lastFeedStatus,
    required this.mqttConnected,
    required this.safeIntervalSec,
    this.scaleValid = false,
    this.ultrasonicValid = false,
    this.busy = false,
    this.lockdown = false,
    this.hopperVerified = false,
    this.presenceAvailable = false,
    this.bowlPresent = false,
    this.simulationMode = false,
    this.contractVersion = 0,
    this.activeCommandId,
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      deviceId: json['device_id'] ?? 'petfeeder_01',
      online: json['online'] == true,
      systemStatus: json['system_status'] ?? 'SAN SANG',
      foodLevelPercent: (json['food_level_percent'] as num?)?.toInt(),
      distanceCm: (json['distance_cm'] as num?)?.toDouble(),
      bowlWeightG: (json['bowl_weight_g'] as num?)?.toDouble(),
      ipAddress: json['ip_address'] ?? '192.168.1.1',
      wifiRssi: (json['wifi_rssi'] ?? -60).toInt(),
      lastSeen: json['last_seen'],
      lastFeedTime: json['last_feed_time'],
      lastFeedPortionG: (json['last_feed_portion_g'] as num?)?.toDouble(),
      lastFeedStatus: json['last_feed_status'] ?? 'CHUA_CHO_AN',
      mqttConnected: json['mqtt_connected'] == true,
      safeIntervalSec: (json['safe_interval_sec'] ?? 180).toInt(),
      scaleValid: json['scale_valid'] == true,
      ultrasonicValid: json['ultrasonic_valid'] == true,
      busy: json['busy'] == true,
      lockdown: json['lockdown'] == true,
      hopperVerified: json['hopper_verified'] == true,
      presenceAvailable: json['bowl_presence_available'] == true,
      bowlPresent: json['bowl_present'] == true,
      simulationMode: json['simulation_mode'] == true,
      contractVersion: json['contract_version'] ?? 0,
      activeCommandId: json['active_command_id'],
    );
  }
}

class FeedingSchedule {
  final String id;
  final String name;
  final String time; // "HH:mm"
  final int portionG;
  final List<String> days;
  final bool enabled;

  FeedingSchedule({
    required this.id,
    required this.name,
    required this.time,
    required this.portionG,
    required this.days,
    required this.enabled,
  });

  factory FeedingSchedule.fromJson(Map<String, dynamic> json) {
    return FeedingSchedule(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Lịch cho ăn',
      time: json['time'] ?? '07:00',
      portionG: (json['portion_g'] ?? 30).toInt(),
      days:
          (json['days'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'],
      enabled: json['enabled'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'time': time,
      'portion_g': portionG,
      'days': days,
      'enabled': enabled,
    };
  }
}

class FeedingRecord {
  final String id;
  final String timestamp;
  final String triggerSource; // "app", "schedule", "button", "override"
  final int targetPortionG;
  final double? actualWeightG;
  final String? commandId;
  final String? retryCommandId;
  final String errorCode;
  final double? cumulativeDeliveredG;
  final double rootTargetG;
  final double portionToleranceG;
  final bool measurementValid;
  final String status; // "SUCCESS", "BLOCKED", "JAM_ERROR", "EMPTY"
  final String message;
  final int durationMs;

  FeedingRecord({
    required this.id,
    required this.timestamp,
    required this.triggerSource,
    required this.targetPortionG,
    required this.actualWeightG,
    required this.status,
    required this.message,
    required this.durationMs,
    this.commandId,
    this.retryCommandId,
    this.errorCode = 'NONE',
    this.cumulativeDeliveredG,
    this.rootTargetG = 0,
    this.portionToleranceG = 3,
    this.measurementValid = false,
  });

  factory FeedingRecord.fromJson(Map<String, dynamic> json) {
    return FeedingRecord(
      id: json['id'] ?? '',
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
      triggerSource: json['trigger_source'] ?? 'app',
      targetPortionG: (json['target_portion_g'] ?? 0).toInt(),
      actualWeightG: json['measurement_valid'] == false
          ? null
          : (json['actual_weight_g'] as num?)?.toDouble(),
      status: json['status'] ?? 'UNKNOWN',
      message: json['message'] ?? '',
      durationMs: (json['duration_ms'] ?? 0).toInt(),
      commandId: json['command_id'],
      retryCommandId: json['retry_command_id'],
      errorCode: json['error_code'] ?? 'NONE',
      cumulativeDeliveredG: (json['cumulative_delivered_g'] as num?)
          ?.toDouble(),
      rootTargetG: (json['root_target_g'] ?? json['target_portion_g'] ?? 0)
          .toDouble(),
      measurementValid: json['measurement_valid'] == true,
      portionToleranceG: (json['portion_tolerance_g'] ?? 3).toDouble(),
    );
  }
}

class AlertNotification {
  final String id;
  final String timestamp;
  final String level; // "error", "warning", "info"
  final String title;
  final String message;
  final bool read;

  AlertNotification({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.title,
    required this.message,
    required this.read,
  });

  factory AlertNotification.fromJson(Map<String, dynamic> json) {
    return AlertNotification(
      id: json['id'] ?? '',
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
      level: json['level'] ?? 'info',
      title: json['title'] ?? 'Thông báo',
      message: json['message'] ?? '',
      read: json['read'] == true,
    );
  }
}
