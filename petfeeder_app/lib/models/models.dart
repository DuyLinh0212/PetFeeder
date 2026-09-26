class DeviceStatus {
  final String deviceId;
  final bool online;
  final String systemStatus;
  final int foodLevelPercent;
  final double distanceCm;
  final double bowlWeightG;
  final String ipAddress;
  final int wifiRssi;
  final String? lastSeen;
  final String? lastFeedTime;
  final double lastFeedPortionG;
  final String lastFeedStatus;
  final bool mqttConnected;
  final int safeIntervalSec;

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
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    return DeviceStatus(
      deviceId: json['device_id'] ?? 'petfeeder_01',
      online: json['online'] == true,
      systemStatus: json['system_status'] ?? 'SAN SANG',
      foodLevelPercent: (json['food_level_percent'] ?? 0).toInt(),
      distanceCm: (json['distance_cm'] ?? 0.0).toDouble(),
      bowlWeightG: (json['bowl_weight_g'] ?? 0.0).toDouble(),
      ipAddress: json['ip_address'] ?? '192.168.1.1',
      wifiRssi: (json['wifi_rssi'] ?? -60).toInt(),
      lastSeen: json['last_seen'],
      lastFeedTime: json['last_feed_time'],
      lastFeedPortionG: (json['last_feed_portion_g'] ?? 0.0).toDouble(),
      lastFeedStatus: json['last_feed_status'] ?? 'CHUA_CHO_AN',
      mqttConnected: json['mqtt_connected'] == true,
      safeIntervalSec: (json['safe_interval_sec'] ?? 180).toInt(),
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
      days: (json['days'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
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
  final double actualWeightG;
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
  });

  factory FeedingRecord.fromJson(Map<String, dynamic> json) {
    return FeedingRecord(
      id: json['id'] ?? '',
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
      triggerSource: json['trigger_source'] ?? 'app',
      targetPortionG: (json['target_portion_g'] ?? 0).toInt(),
      actualWeightG: (json['actual_weight_g'] ?? 0.0).toDouble(),
      status: json['status'] ?? 'UNKNOWN',
      message: json['message'] ?? '',
      durationMs: (json['duration_ms'] ?? 0).toInt(),
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
