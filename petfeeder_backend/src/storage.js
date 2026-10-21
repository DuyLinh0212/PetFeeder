const fs = require("fs");
const path = require("path");
const { randomUUID } = require("crypto");
const config = require("./config");
const { defaults, fields } = require("./deviceConfig");
const DB_FILE =
  process.env.PETFEEDER_DB_FILE ||
  path.join(__dirname, "..", "data", "database.json");
fs.mkdirSync(path.dirname(DB_FILE), { recursive: true });
const initial = {
  schema_version: 2,
  device_state: {
    device_id: config.device.id,
    online: false,
    system_status: "UNKNOWN",
    food_level_percent: null,
    distance_cm: null,
    bowl_weight_g: null,
    ip_address: null,
    wifi_rssi: null,
    last_seen: null,
    last_feed_time: null,
    last_feed_portion_g: 0,
    last_feed_status: "CHUA_CHO_AN",
    contract_version: 0,
    scale_valid: false,
    ultrasonic_valid: false,
    bowl_presence_available: false,
    hopper_verified: false,
    lockdown: false,
    busy: false,
  },
  device_config: { ...defaults, lockdown: false },
  schedules: [],
  feeding_history: [],
  alerts: [],
  commands: {},
  processed_event_ids: [],
};
let state = structuredClone(initial);
if (fs.existsSync(DB_FILE)) {
  // Corrupt data must not silently become a fresh budget/history.
  const parsed = JSON.parse(fs.readFileSync(DB_FILE, "utf8"));
  if (parsed.schema_version !== 2 && !fs.existsSync(DB_FILE + ".v1.bak"))
    fs.copyFileSync(DB_FILE, DB_FILE + ".v1.bak");
  state = {
    ...state,
    ...parsed,
    schema_version: 2,
    device_state: {
      ...initial.device_state,
      ...parsed.device_state,
      online: false,
    },
    device_config: { ...initial.device_config },
    commands: parsed.commands || {},
    processed_event_ids: parsed.processed_event_ids || [],
  };
  for (const key of [...Object.keys(fields), "lockdown"])
    if (parsed.device_config?.[key] !== undefined)
      state.device_config[key] = parsed.device_config[key];
}
function save() {
  const temporary = DB_FILE + ".tmp";
  const fd = fs.openSync(temporary, "w");
  try {
    fs.writeFileSync(fd, JSON.stringify(state, null, 2));
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
  fs.renameSync(temporary, DB_FILE);
}
function mutate(fn) {
  const previous = structuredClone(state);
  try {
    const value = fn();
    save();
    return value;
  } catch (error) {
    state = previous;
    throw error;
  }
}
const now = () => new Date().toISOString();
const sorted = (list) =>
  [...list].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
const pending = (s) =>
  ["PUBLISHING", "ACCEPTED", "DISPENSING", "PAUSED", "UNKNOWN"].includes(s);
const iso = (value) =>
  typeof value === "number" && value > 0
    ? new Date(value * 1000).toISOString()
    : null;
function historyRecord(record) {
  const result = {
    id: record.command_id || randomUUID(),
    timestamp: iso(record.completed_at) || iso(record.started_at) || now(),
    trigger_source: record.source || record.trigger_source || "unknown",
    message: record.message || "",
    duration_ms: record.duration_ms || 0,
    ...record,
  };
  if (record.measurement_valid === false || record.actual_weight_g == null)
    result.actual_weight_g = null;
  return result;
}
module.exports = {
  getDeviceState: () => structuredClone(state.device_state),
  updateDeviceState: (patch) =>
    mutate(() => (state.device_state = { ...state.device_state, ...patch })),
  getDeviceConfig: () => structuredClone(state.device_config),
  updateDeviceConfig: (patch) =>
    mutate(() => (state.device_config = { ...state.device_config, ...patch })),
  getSchedules: () => structuredClone(state.schedules),
  addSchedule: (sch) =>
    mutate(() => {
      const s = {
        id: randomUUID(),
        name: "Lịch cho ăn",
        portion_g: 30,
        days: ["T2", "T3", "T4", "T5", "T6", "T7", "CN"],
        enabled: true,
        ...sch,
        created_at: now(),
      };
      state.schedules.push(s);
      return s;
    }),
  updateSchedule: (id, patch) =>
    mutate(() => {
      const s = state.schedules.find((s) => s.id === id);
      return s ? Object.assign(s, patch, { id }) : null;
    }),
  deleteSchedule: (id) =>
    mutate(() => {
      const i = state.schedules.findIndex((s) => s.id === id);
      if (i < 0) return false;
      state.schedules.splice(i, 1);
      return true;
    }),
  getFeedingHistory: (limit = 50) =>
    structuredClone(sorted(state.feeding_history).slice(0, limit)),
  addFeedingRecord: (record) =>
    mutate(() => {
      const r = historyRecord(record);
      state.feeding_history.unshift(r);
      state.feeding_history = state.feeding_history.slice(0, 200);
      return r;
    }),
  clearFeedingHistory: () =>
    mutate(() => {
      state.feeding_history = [];
    }),
  getCommand: (id) => structuredClone(state.commands[id] || null),
  getCommands: () => structuredClone(Object.values(state.commands)),
  createCommand: (command) =>
    mutate(() => {
      if (state.commands[command.command_id])
        return state.commands[command.command_id];
      state.commands[command.command_id] = command;
      return command;
    }),
  updateCommand: (id, patch) =>
    mutate(() => {
      if (!state.commands[id]) return null;
      return Object.assign(state.commands[id], patch);
    }),
  applyResult: (payload) => {
    const prior = state.commands[payload.command_id];
    if (
      state.processed_event_ids.includes(payload.event_id) ||
      prior?.revision >= payload.revision
    )
      return false;
    return mutate(() => {
      state.processed_event_ids.push(payload.event_id);
      state.processed_event_ids = state.processed_event_ids.slice(-20000);
      const command = { ...prior, ...payload };
      state.commands[payload.command_id] = command;
      if (
        command.retry_of &&
        command.status !== "REJECTED" &&
        state.commands[command.retry_of]
      ) {
        const parent = state.commands[command.retry_of];
        parent.retry_command_id = command.command_id;
        if (parent.status === "PAUSED") parent.status = "RESUMED";
        const row = state.feeding_history.find(
          (x) => x.command_id === parent.command_id,
        );
        if (row)
          Object.assign(row, {
            status: parent.status,
            retry_command_id: command.command_id,
          });
      }
      // Status updates replace one row; clearing visible history never clears command identity.
      if (!["ACCEPTED", "DISPENSING"].includes(command.status)) {
        const r = historyRecord(command);
        const i = state.feeding_history.findIndex(
          (x) => x.command_id === command.command_id,
        );
        if (i < 0) state.feeding_history.unshift(r);
        else state.feeding_history[i] = r;
        state.feeding_history = state.feeding_history.slice(0, 200);
        if (
          command.started_at &&
          !["REJECTED", "BLOCKED_DUPLICATE"].includes(command.status)
        ) {
          state.device_state.last_feed_time =
            iso(command.completed_at) || iso(command.started_at);
          state.device_state.last_feed_portion_g = command.actual_weight_g;
          state.device_state.last_feed_status = command.status;
        }
      }
      if (!pending(command.status) && command.error_code !== "NONE") {
        state.alerts.unshift({
          id: payload.event_id,
          timestamp: now(),
          level: "warning",
          title: "Phiên cho ăn cần kiểm tra",
          message: command.error_code,
          read: false,
        });
        state.alerts = state.alerts.slice(0, 100);
      }
      return true;
    });
  },
  acceptEvent: (id) => {
    if (state.processed_event_ids.includes(id)) return false;
    return mutate(() => {
      state.processed_event_ids.push(id);
      state.processed_event_ids = state.processed_event_ids.slice(-20000);
      return true;
    });
  },
  getAlerts: () => structuredClone(sorted(state.alerts)),
  addAlert: (alert) =>
    mutate(() => {
      const a = {
        id: randomUUID(),
        timestamp: now(),
        level: "warning",
        title: "Cảnh báo hệ thống",
        message: "",
        ...alert,
        read: false,
      };
      state.alerts.unshift(a);
      state.alerts = state.alerts.slice(0, 100);
      return a;
    }),
  markAlertRead: (id) =>
    mutate(() => {
      const a = state.alerts.find((a) => a.id === id);
      if (!a) return false;
      a.read = true;
      return true;
    }),
  clearAlerts: () =>
    mutate(() => {
      state.alerts = [];
    }),
};
