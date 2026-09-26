const fs = require('fs');
const path = require('path');
const config = require('./config');

const DATA_DIR = path.join(__dirname, '..', 'data');
const DB_FILE = path.join(DATA_DIR, 'database.json');

// Ensure data directory exists
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// Initial default state
const defaultState = {
  device_state: {
    device_id: config.device.id,
    online: false,
    system_status: "SAN SANG",
    food_level_percent: 85,
    distance_cm: 5.5,
    bowl_weight_g: 0.0,
    ip_address: "192.168.1.50",
    wifi_rssi: -58,
    last_seen: new Date().toISOString(),
    last_feed_time: null,
    last_feed_portion_g: 0,
    last_feed_status: "CHUA_CHO_AN"
  },
  device_config: {
    safe_interval_sec: config.device.safeIntervalSec,
    tank_height_cm: config.device.tankHeightCm,
    empty_threshold_cm: config.device.emptyThresholdCm,
    pulse_step_angle: 90,
    pulse_step_ms: 600,
    anti_jam_max_retries: 3
  },
  schedules: [
    {
      id: "sch_1",
      name: "Bữa sáng",
      time: "07:00",
      portion_g: 40,
      days: ["T2", "T3", "T4", "T5", "T6", "T7", "CN"],
      enabled: true,
      created_at: new Date(Date.now() - 86400000 * 2).toISOString()
    },
    {
      id: "sch_2",
      name: "Bữa trưa",
      time: "12:30",
      portion_g: 35,
      days: ["T2", "T3", "T4", "T5", "T6", "T7", "CN"],
      enabled: true,
      created_at: new Date(Date.now() - 86400000 * 2).toISOString()
    },
    {
      id: "sch_3",
      name: "Bữa tối",
      time: "19:00",
      portion_g: 45,
      days: ["T2", "T3", "T4", "T5", "T6", "T7", "CN"],
      enabled: true,
      created_at: new Date(Date.now() - 86400000 * 2).toISOString()
    }
  ],
  feeding_history: [
    {
      id: "feed_init_1",
      timestamp: new Date(Date.now() - 3600000 * 4).toISOString(),
      trigger_source: "schedule",
      target_portion_g: 40,
      actual_weight_g: 39.5,
      status: "SUCCESS",
      message: "Cấp thức ăn tự động theo lịch Bữa sáng hoàn tất",
      duration_ms: 3200
    },
    {
      id: "feed_init_2",
      timestamp: new Date(Date.now() - 3600000 * 8).toISOString(),
      trigger_source: "app",
      target_portion_g: 20,
      actual_weight_g: 20.2,
      status: "SUCCESS",
      message: "Cho ăn ngay từ Mobile App thành công",
      duration_ms: 2100
    }
  ],
  alerts: [
    {
      id: "alert_1",
      timestamp: new Date(Date.now() - 3600000 * 2).toISOString(),
      level: "info",
      title: "Hệ thống sẵn sàng",
      message: "Bộ điều khiển ESP32 đã kết nối vào mạng Wi-Fi và đồng bộ dữ liệu",
      read: true
    }
  ]
};

// Memory store
let memoryState = { ...defaultState };

// Load persistent data from disk
function loadFromDisk() {
  try {
    if (fs.existsSync(DB_FILE)) {
      const raw = fs.readFileSync(DB_FILE, 'utf-8');
      const parsed = JSON.parse(raw);
      memoryState = {
        ...defaultState,
        ...parsed,
        device_state: { ...defaultState.device_state, ...(parsed.device_state || {}) },
        device_config: { ...defaultState.device_config, ...(parsed.device_config || {}) }
      };
      console.log(' [Storage] Loaded persisted database successfully from disk.');
    } else {
      saveToDisk();
      console.log(' [Storage] Initialized new database file.');
    }
  } catch (err) {
    console.error(' [Storage Error] Failed to read database.json:', err.message);
    memoryState = { ...defaultState };
  }
}

// Persist memoryState to disk asynchronously
function saveToDisk() {
  try {
    fs.writeFileSync(DB_FILE, JSON.stringify(memoryState, null, 2), 'utf-8');
  } catch (err) {
    console.error(' [Storage Error] Failed to save database.json:', err.message);
  }
}

// Initialize on require
loadFromDisk();

module.exports = {
  // Device State
  getDeviceState: () => memoryState.device_state,
  updateDeviceState: (patch) => {
    memoryState.device_state = {
      ...memoryState.device_state,
      ...patch,
      last_seen: new Date().toISOString()
    };
    saveToDisk();
    return memoryState.device_state;
  },

  // Device Config
  getDeviceConfig: () => memoryState.device_config,
  updateDeviceConfig: (patch) => {
    memoryState.device_config = {
      ...memoryState.device_config,
      ...patch
    };
    saveToDisk();
    return memoryState.device_config;
  },

  // Schedules
  getSchedules: () => memoryState.schedules,
  addSchedule: (sch) => {
    const newSch = {
      id: "sch_" + Date.now(),
      name: sch.name || "Lịch cho ăn",
      time: sch.time,
      portion_g: sch.portion_g || 30,
      days: sch.days || ["T2", "T3", "T4", "T5", "T6", "T7", "CN"],
      enabled: sch.enabled !== undefined ? sch.enabled : true,
      created_at: new Date().toISOString()
    };
    memoryState.schedules.push(newSch);
    saveToDisk();
    return newSch;
  },
  updateSchedule: (id, patch) => {
    const idx = memoryState.schedules.findIndex(s => s.id === id);
    if (idx === -1) return null;
    memoryState.schedules[idx] = {
      ...memoryState.schedules[idx],
      ...patch
    };
    saveToDisk();
    return memoryState.schedules[idx];
  },
  deleteSchedule: (id) => {
    const idx = memoryState.schedules.findIndex(s => s.id === id);
    if (idx === -1) return false;
    memoryState.schedules.splice(idx, 1);
    saveToDisk();
    return true;
  },

  // Feeding History
  getFeedingHistory: (limit = 50) => {
    return [...memoryState.feeding_history]
      .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
      .slice(0, limit);
  },
  addFeedingRecord: (record) => {
    const newRecord = {
      id: "feed_" + Date.now(),
      timestamp: record.timestamp || new Date().toISOString(),
      trigger_source: record.trigger_source || "unknown",
      target_portion_g: record.target_portion_g || 0,
      actual_weight_g: record.actual_weight_g || 0,
      status: record.status || "UNKNOWN",
      message: record.message || "",
      duration_ms: record.duration_ms || 0
    };
    memoryState.feeding_history.unshift(newRecord);
    // Keep max 200 history records
    if (memoryState.feeding_history.length > 200) {
      memoryState.feeding_history.pop();
    }

    // Update last feed time in device_state
    if (record.status === 'SUCCESS' || record.status === 'HOAN TAT') {
      memoryState.device_state.last_feed_time = newRecord.timestamp;
      memoryState.device_state.last_feed_portion_g = newRecord.actual_weight_g;
      memoryState.device_state.last_feed_status = 'SUCCESS';
    }

    saveToDisk();
    return newRecord;
  },
  clearFeedingHistory: () => {
    memoryState.feeding_history = [];
    saveToDisk();
  },

  // Alerts
  getAlerts: () => {
    return [...memoryState.alerts].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
  },
  addAlert: (alert) => {
    const newAlert = {
      id: "alt_" + Date.now(),
      timestamp: alert.timestamp || new Date().toISOString(),
      level: alert.level || "warning", // error, warning, info
      title: alert.title || "Cảnh báo hệ thống",
      message: alert.message || "",
      read: false
    };
    memoryState.alerts.unshift(newAlert);
    if (memoryState.alerts.length > 100) {
      memoryState.alerts.pop();
    }
    saveToDisk();
    return newAlert;
  },
  markAlertRead: (id) => {
    const alert = memoryState.alerts.find(a => a.id === id);
    if (alert) {
      alert.read = true;
      saveToDisk();
      return true;
    }
    return false;
  },
  clearAlerts: () => {
    memoryState.alerts = [];
    saveToDisk();
  }
};
