const mqtt = require('mqtt');
const config = require('./config');
const storage = require('./storage');

let client = null;
let isConnected = false;

function initMQTT() {
  console.log(`[MQTT] Connecting to broker at ${config.mqtt.brokerUrl}...`);

  client = mqtt.connect(config.mqtt.brokerUrl, {
    clientId: `petfeeder_backend_${Math.random().toString(16).substring(2, 8)}`,
    clean: true,
    connectTimeout: 5000,
    reconnectPeriod: 3000
  });

  client.on('connect', () => {
    isConnected = true;
    console.log(` [MQTT] Connected successfully to ${config.mqtt.brokerUrl}`);

    // Subscribe to topics from ESP32
    const topicsToSub = [
      config.mqtt.topics.telemetry,
      config.mqtt.topics.events,
      config.mqtt.topics.alerts
    ];

    client.subscribe(topicsToSub, (err) => {
      if (err) {
        console.error(' [MQTT] Subscription error:', err.message);
      } else {
        console.log(` [MQTT] Subscribed to topics:`, topicsToSub.join(', '));
      }
    });

    // Auto sync schedules on connect
    syncSchedulesToDevice();
  });

  client.on('message', (topic, message) => {
    try {
      const payloadStr = message.toString();
      let payload;
      try {
        payload = JSON.parse(payloadStr);
      } catch (e) {
        payload = { raw: payloadStr };
      }

      handleIncomingMessage(topic, payload);
    } catch (err) {
      console.error(` [MQTT Error] Failed processing message on ${topic}:`, err.message);
    }
  });

  client.on('error', (err) => {
    console.error(' [MQTT Error]:', err.message);
  });

  client.on('close', () => {
    if (isConnected) {
      console.log(' [MQTT] Disconnected from broker.');
    }
    isConnected = false;
  });

  client.on('reconnect', () => {
    console.log(' [MQTT] Reconnecting to broker...');
  });

  // Watchdog to mark device offline if no telemetry received for 15s
  setInterval(() => {
    const state = storage.getDeviceState();
    if (state.last_seen) {
      const diffMs = Date.now() - new Date(state.last_seen).getTime();
      if (diffMs > 15000 && state.online) {
        storage.updateDeviceState({ online: false });
        console.log(' [Watchdog] Device marked OFFLINE (no telemetry for > 15s)');
      }
    }
  }, 5000);
}

function handleIncomingMessage(topic, payload) {
  // Telemetry
  if (topic === config.mqtt.topics.telemetry) {
    const patch = {
      online: true,
      system_status: payload.status || "SAN SANG",
      food_level_percent: payload.food_level_percent !== undefined ? payload.food_level_percent : 0,
      distance_cm: payload.distance_cm !== undefined ? payload.distance_cm : 0,
      bowl_weight_g: payload.bowl_weight_g !== undefined ? payload.bowl_weight_g : 0,
      ip_address: payload.ip || "192.168.1.100",
      wifi_rssi: payload.rssi !== undefined ? payload.rssi : -60
    };
    storage.updateDeviceState(patch);
  }

  // Feed Result & Bowl Events
  else if (topic === config.mqtt.topics.events) {
    console.log(' [MQTT] Received event from ESP32:', payload);

    // Xử lý sự kiện biến động bát ngoài phiên cấp (N13, N14)
    if (payload.event === 'BOWL_EVENT') {
      console.log(` [MQTT] Bowl Event: ${payload.type} (Delta: ${payload.delta_g}g, Current: ${payload.current_bowl_weight_g}g, Cause: ${payload.cause})`);
      if (payload.type === 'MANUAL_REFILL') {
        storage.addAlert({
          level: 'info',
          title: 'Nạp thức ăn thủ công',
          message: `Phát hiện chủ nuôi đã nạp thêm ${payload.delta_g}g thức ăn trực tiếp vào bát.`
        });
      } else if (payload.type === 'WEIGHT_DECREASED') {
        storage.addAlert({
          level: 'info',
          title: 'Khối lượng bát giảm',
          message: `Khối lượng thức ăn trong bát giảm ${Math.abs(payload.delta_g)}g (Nguyên nhân: ${payload.cause || 'UNKNOWN_CAUSE'}).`
        });
      }
      return;
    }

    const targetPortion = payload.target_portion_g !== undefined ? payload.target_portion_g : (payload.target_portion || payload.portion || 0);
    const actualWeight = payload.actual_weight_g !== undefined ? payload.actual_weight_g : (payload.actual_weight || 0);

    storage.addFeedingRecord({
      command_id: payload.command_id || null,
      trigger_source: payload.trigger_source || payload.source || "esp32",
      target_portion_g: targetPortion,
      actual_weight_g: actualWeight,
      status: payload.status || "UNKNOWN",
      error_code: payload.error_code || "NONE",
      message: payload.message || `Cấp thức ăn trạng thái: ${payload.status}`,
      duration_ms: payload.duration_ms || 0
    });

    // Check if error status to generate immediate alert
    if (payload.status === 'JAM_ERROR') {
      storage.addAlert({
        level: 'error',
        title: 'CẢNH BÁO KẸT HẠT!',
        message: `Cơ cấu cấp thức ăn bị kẹt tại thời điểm ${new Date().toLocaleTimeString('vi-VN')}. ESP32 đã thử tự gỡ nhưng không thành công!`
      });
      storage.updateDeviceState({ system_status: "LOI KET HAT" });
    } else if (payload.status === 'FOOD_EMPTY' || payload.status === 'EMPTY') {
      storage.addAlert({
        level: 'error',
        title: 'HẾT THỨC ĂN TRONG HỘP!',
        message: 'Hộp chứa đã hết thức ăn. Vui lòng nạp thêm thức ăn cho thú cưng.'
      });
      storage.updateDeviceState({ system_status: "LOI: HET HAT" });
    } else if (payload.status === 'BLOCKED_DUPLICATE' || payload.status === 'BLOCKED') {
      storage.addAlert({
        level: 'warning',
        title: 'Lệnh cho ăn bị chặn',
        message: 'Hệ thống đã chặn lệnh cho ăn vì thời gian quá gần với bữa ăn trước hoặc trùng lặp.'
      });
    } else if (payload.status === 'SENSOR_ERROR') {
      storage.addAlert({
        level: 'error',
        title: 'LỖI CẢM BIẾN!',
        message: `Phát hiện lỗi phần cứng cảm biến: ${payload.error_code || 'SENSOR_FAULT'}. Vui lòng kiểm tra kết nối dây!`
      });
    }
  }

  // General Alerts
  else if (topic === config.mqtt.topics.alerts) {
    console.log(' [MQTT] Received alert from ESP32:', payload);
    storage.addAlert({
      level: payload.level || "warning",
      title: payload.title || "Cảnh báo từ ESP32",
      message: payload.message || JSON.stringify(payload)
    });
  }
}

// Publish feed command to ESP32
function publishFeedCommand(options) {
  if (!client || !isConnected) {
    console.warn(' [MQTT] Warning: publishing command while MQTT not connected to broker!');
  }

  const nowSec = Math.floor(Date.now() / 1000);
  const payload = {
    command_id: options.command_id || `cmd_${nowSec}_${Math.random().toString(16).substring(2, 6)}`,
    command: "FEED",
    portion: options.portion || 30,
    target_portion_g: options.portion || 30,
    override: !!options.override,
    source: options.source || "app",
    created_at: nowSec,
    expires_at: nowSec + 60,
    timestamp: nowSec
  };

  const payloadStr = JSON.stringify(payload);
  client.publish(config.mqtt.topics.command, payloadStr, { qos: 1 }, (err) => {
    if (err) {
      console.error(' [MQTT] Failed to publish feed command:', err.message);
    } else {
      console.log(` [MQTT] Published feed command: ${payloadStr}`);
    }
  });

  return payload;
}

// Sync schedules to ESP32 for offline execution (FR-04)
function syncSchedulesToDevice() {
  if (!client || !isConnected) return;

  const schedules = storage.getSchedules();
  // Filter active schedules
  const syncList = schedules.map(s => ({
    id: s.id,
    time: s.time, // "HH:mm"
    portion: s.portion_g,
    enabled: s.enabled
  }));

  const payloadStr = JSON.stringify({
    action: "SYNC_SCHEDULES",
    count: syncList.length,
    schedules: syncList,
    timestamp: Math.floor(Date.now() / 1000)
  });

  client.publish(config.mqtt.topics.schedulesSync, payloadStr, { qos: 1, retain: true }, (err) => {
    if (err) {
      console.error(' [MQTT] Failed to sync schedules:', err.message);
    } else {
      console.log(` [MQTT] Synced ${syncList.length} schedules to ESP32`);
    }
  });
}

// Publish config parameters to ESP32
function syncConfigToDevice() {
  if (!client || !isConnected) return;

  const cfg = storage.getDeviceConfig();
  const payloadStr = JSON.stringify({
    action: "SYNC_CONFIG",
    config: cfg
  });

  client.publish(config.mqtt.topics.config, payloadStr, { qos: 1, retain: true });
}

module.exports = {
  initMQTT,
  publishFeedCommand,
  syncSchedulesToDevice,
  syncConfigToDevice,
  isMQTTConnected: () => isConnected
};
