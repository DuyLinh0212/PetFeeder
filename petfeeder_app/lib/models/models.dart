class DeviceStatus {
  final String deviceId;
  final bool online;
  final String systemStatus;
  final double? bowlWeightG;
  final int? foodLevelPercent;
  final double? distanceCm;
  final String ipAddress;
  final int wifiRssi;
  final String? lastSeen;
  final bool mqttConnected;
  final int minIntervalSec;
  final int maxPortionG;
  final int dailyLimitG;
  final int maxDailyFeeds;
  final int bowlCapacityG;
  final bool requirePet;
  final double dailyDispensedG;
  final int dailyFeedCount;
  final bool locked;
  final bool timeValid;
  final String sensorMode;

  const DeviceStatus({
    required this.deviceId,
    required this.online,
    required this.systemStatus,
    required this.bowlWeightG,
    this.foodLevelPercent,
    this.distanceCm,
    required this.ipAddress,
    required this.wifiRssi,
    required this.lastSeen,
    required this.mqttConnected,
    required this.minIntervalSec,
    required this.maxPortionG,
    required this.dailyLimitG,
    required this.maxDailyFeeds,
    required this.bowlCapacityG,
    required this.requirePet,
    required this.dailyDispensedG,
    required this.dailyFeedCount,
    required this.locked,
    required this.timeValid,
    required this.sensorMode,
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    final daily = json['daily'] is Map
        ? Map<String, dynamic>.from(json['daily'] as Map)
        : const <String, dynamic>{};
    return DeviceStatus(
      deviceId: json['device_id'] as String? ?? 'petfeeder_01',
      online: json['online'] == true,
      systemStatus: json['system_status'] as String? ?? 'SAN SANG',
      bowlWeightG: (json['bowl_weight_g'] as num?)?.toDouble(),
      foodLevelPercent: (json['food_level_percent'] as num?)?.toInt(),
      distanceCm: (json['distance_cm'] as num?)?.toDouble(),
      ipAddress: json['ip_address'] as String? ?? '',
      wifiRssi: (json['wifi_rssi'] as num?)?.toInt() ?? 0,
      lastSeen: json['last_seen'] as String?,
      mqttConnected: json['mqtt_connected'] == true,
      minIntervalSec: (json['min_interval_s'] as num?)?.toInt() ?? 180,
      maxPortionG: (json['max_portion_g'] as num?)?.toInt() ?? 100,
      dailyLimitG: (json['daily_limit_g'] as num?)?.toInt() ?? 200,
      maxDailyFeeds: (json['max_daily_feeds'] as num?)?.toInt() ?? 6,
      bowlCapacityG: (json['bowl_capacity_g'] as num?)?.toInt() ?? 150,
      requirePet: json['require_pet'] == true,
      dailyDispensedG: (daily['actual_dispensed_g'] as num?)?.toDouble() ?? 0,
      dailyFeedCount: (daily['confirmed_sessions'] as num?)?.toInt() ?? 0,
      locked: json['locked'] == true,
      timeValid: json['time_valid'] == true,
      sensorMode: json['sensor_mode'] as String? ?? 'UNKNOWN',
    );
  }
}

class FeedingSchedule {
  final String id;
  final String name;
  final String time;
  final int portionG;
  final List<String> days;
  final bool enabled;

  const FeedingSchedule({
    required this.id,
    required this.name,
    required this.time,
    required this.portionG,
    required this.days,
    required this.enabled,
  });

  factory FeedingSchedule.fromJson(Map<String, dynamic> json) {
    return FeedingSchedule(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Lịch cho ăn',
      time: json['time'] as String? ?? '07:00',
      portionG: (json['portion_g'] as num?)?.toInt() ?? 30,
      days:
          (json['days'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'],
      enabled: json['enabled'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'time': time,
    'portion_g': portionG,
    'days': days,
    'enabled': enabled,
  };
}
