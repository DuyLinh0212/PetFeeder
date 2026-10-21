const mqtt = require("mqtt");
const config = require("./config");
const storage = require("./storage");
const { validate, fields } = require("./deviceConfig");
let client = null,
  connected = false,
  watchdog;
const finite = (value) => typeof value === "number" && Number.isFinite(value);
function handleIncomingMessage(topic, p) {
  if (!p || typeof p !== "object") return;
  if (topic === config.mqtt.topics.telemetry) {
    if (p.device_id && p.device_id !== config.device.id) return;
    const v2 = p.contract_version === 2;
    const patch = {
      ...p,
      online: true,
      system_status: p.status || "UNKNOWN",
      last_seen: new Date().toISOString(),
      contract_version: v2 ? 2 : 1,
      lockdown: p.lockdown === true || p.is_safety_lockout === true,
      hopper_verified: v2 && p.hopper_verified === true,
      bowl_presence_available: v2 && p.bowl_presence_available === true,
      bowl_present: v2 && p.bowl_present === true,
      busy: v2 && p.busy === true,
      active_command_id:
        typeof p.active_command_id === "string" && p.active_command_id
          ? p.active_command_id
          : null,

      scale_valid: v2 && p.scale_valid === true,
      ultrasonic_valid: v2 && p.ultrasonic_valid === true,
      bowl_weight_g:
        v2 && p.scale_valid && finite(p.bowl_weight_g) ? p.bowl_weight_g : null,
      distance_cm:
        v2 && p.ultrasonic_valid && finite(p.distance_cm)
          ? p.distance_cm
          : null,
      food_level_percent:
        v2 && p.ultrasonic_valid && finite(p.food_level_percent)
          ? p.food_level_percent
          : null,
      food_quality: "UNVERIFIED",
      ip_address: p.ip || null,
      wifi_rssi: finite(p.rssi) ? p.rssi : null,
    };
    storage.updateDeviceState(patch);
    if (v2 && p.config_snapshot) {
      const actual = Object.fromEntries(
        Object.entries(p.config_snapshot).filter(
          ([key]) => fields[key] || key === "lockdown",
        ),
      );
      const current = storage.getDeviceConfig();
      if (
        validate(actual, current) &&
        Object.entries(actual).some(([key, value]) => current[key] !== value)
      )
        storage.updateDeviceConfig(actual);
    }
  } else if (topic === config.mqtt.topics.events) {
    if (typeof p.event_id !== "string" || p.event_id.length > 160) return;
    if (p.event === "BOWL_EVENT") {
      if (!storage.acceptEvent(p.event_id)) return;
      storage.addAlert({
        title:
          p.type === "REFILL_SUSPECTED"
            ? "Cần xác nhận hộp hạt"
            : "Khối lượng bát thay đổi",
        message: `${p.type}: ${p.delta_g ?? "?"} g · ${p.cause || "UNKNOWN_CAUSE"}`,
        level: "info",
      });
      return;
    }
    const statuses = [
      "ACCEPTED",
      "DISPENSING",
      "PAUSED",
      "SUCCESS",
      "PARTIAL",
      "REJECTED",
      "BLOCKED_DUPLICATE",
      "FOOD_EMPTY",
      "SENSOR_ERROR",
      "JAM_ERROR",
      "INTERRUPTED",
      "TIMEOUT",
      "COMMAND_EXPIRED",
    ];
    if (
      typeof p.command_id !== "string" ||
      !p.command_id ||
      p.command_id.length > 64 ||
      !Number.isInteger(p.revision) ||
      p.revision < 1 ||
      !statuses.includes(p.status)
    )
      return;
    if (!finite(p.target_portion_g) || typeof p.measurement_valid !== "boolean")
      return;
    if (
      p.measurement_valid &&
      (!finite(p.actual_weight_g) || p.actual_weight_g < 0)
    )
      return;
    if (
      p.status === "SUCCESS" &&
      (!p.measurement_valid ||
        Math.abs(p.actual_weight_g - p.target_portion_g) >
          (finite(p.portion_tolerance_g) &&
          p.portion_tolerance_g > 0 &&
          p.portion_tolerance_g <= 10
            ? p.portion_tolerance_g
            : storage.getDeviceConfig().portion_tolerance_g))
    )
      return;
    storage.applyResult({
      ...p,
      actual_weight_g: p.measurement_valid ? p.actual_weight_g : null,
    });
  } else if (
    topic === config.mqtt.topics.alerts &&
    typeof p.event_id === "string" &&
    storage.acceptEvent(p.event_id)
  ) {
    storage.addAlert({ level: p.level, title: p.title, message: p.message });
  }
}
function publish(topic, payload, retain = false) {
  if (!connected || !client) return Promise.reject(new Error("MQTT_OFFLINE"));
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("MQTT_ACK_TIMEOUT")), 4000);
    client.publish(
      topic,
      JSON.stringify(payload),
      { qos: 1, retain },
      (error) => {
        clearTimeout(timer);
        if (error) reject(error);
        else resolve(payload);
      },
    );
  });
}
function syncSchedulesToDevice() {
  const days = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"];
  return publish(
    config.mqtt.topics.schedulesSync,
    {
      schedules: storage.getSchedules().map((s) => ({
        id: s.id,
        time: s.time,
        portion: s.portion_g,
        enabled: s.enabled,
        days_mask: (s.days || days).reduce(
          (mask, d) => mask | (1 << days.indexOf(d)),
          0,
        ),
      })),
    },
    true,
  ).catch((error) => {
    console.error("[MQTT schedules]", error.message);
  });
}
function syncConfigToDevice(patch = storage.getDeviceConfig()) {
  // Owner acknowledgements are transient; retained confirmation would approve a later refill.
  return publish(config.mqtt.topics.config, { config: patch }, false);
}
function initMQTT(factory = mqtt.connect) {
  client = factory(config.mqtt.brokerUrl, {
    clientId: `petfeeder_backend_${require("crypto").randomUUID()}`,
    clean: true,
    connectTimeout: 5000,
    reconnectPeriod: 3000,
  });
  client.on("connect", () => {
    connected = true;
    client.subscribe([
      config.mqtt.topics.telemetry,
      config.mqtt.topics.events,
      config.mqtt.topics.alerts,
    ]);
    syncSchedulesToDevice(); /* Device NVS owns safety/config after reboot. */
  });
  client.on("message", (topic, bytes, packet) => {
    try {
      if (packet?.retain) return;
      handleIncomingMessage(topic, JSON.parse(bytes.toString()));
    } catch (error) {
      console.error("[MQTT input]", error.message);
    }
  });
  client.on("error", (error) => console.error("[MQTT]", error.message));
  client.on("close", () => {
    connected = false;
  });
  watchdog = setInterval(() => {
    const s = storage.getDeviceState();
    if (s.online && Date.now() - Date.parse(s.last_seen) > 15000)
      storage.updateDeviceState({ online: false });
  }, 5000);
  watchdog.unref();
  return client;
}
module.exports = {
  initMQTT,
  handleIncomingMessage,
  syncSchedulesToDevice,
  syncConfigToDevice,
  publishFeedCommand: (payload) => publish(config.mqtt.topics.command, payload),
  isMQTTConnected: () => connected,
  close: () => {
    clearInterval(watchdog);
    client?.end();
    connected = false;
  },
};
