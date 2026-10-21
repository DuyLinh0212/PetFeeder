#include "feeding_controller.h"
#include <Adafruit_SSD1306.h>
#include <Arduino.h>
#include <ArduinoJson.h>
#include <ESP32Servo.h>
#include <HX711.h>
#include <Preferences.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <Wire.h>
#include <deque>
#include <limits>
#include <time.h>
#include <type_traits>

// Physical drivers never silently switch to simulated readings.
#define PIN_BUTTON 4
#define PIN_TRIG 5
#define PIN_ECHO 18
#define PIN_HX711_DT 19
#define PIN_HX711_SCK 23
#define PIN_SERVO_FEED 13
#define PIN_SERVO_ANTI 12
#define PIN_LED_GREEN 2
#define PIN_LED_RED 15
#define PIN_BUZZER 14
#ifndef PETFEEDER_BOWL_PRESENT_PIN
#define PETFEEDER_BOWL_PRESENT_PIN -1
#endif
#ifndef PETFEEDER_LID_PIN
#define PETFEEDER_LID_PIN -1
#endif
const char *PREFIX = "duylinh0212/petfeeder/v1";
const String commandTopic = String(PREFIX) + "/command";
const String configTopic = String(PREFIX) + "/config/v2";
const String scheduleTopic = String(PREFIX) + "/schedules/sync";
const String telemetryTopic = String(PREFIX) + "/telemetry";
const String eventTopic = String(PREFIX) + "/events";
WiFiClient network;
PubSubClient mqtt(network);
Preferences prefs;
HX711 scale;
Servo feedServo, antiServo;
Adafruit_SSD1306 display(128, 64, &Wire, -1);
feeder::Controller controller;
bool oledReady = false, nvsReady = false;
uint32_t lastTelemetry = 0, lastConnect = 0, lastScreen = 0;
uint32_t bootSequence = 0, localSequence = 0, bowlSequence = 0;
String clientId;
std::deque<String> outbox;
String serialLine;
double scaleFactor = 0, scaleOffset = 0;
std::vector<double> samples;
uint32_t lastSample = 0, lastScaleGood = 0, lastDistance = 0;
unsigned ultrasonicMisses = 0, sampleSequence = 0;
volatile uint32_t buttonDownAt = 0, buttonDuration = 0;
volatile bool buttonReady = false, buttonDown = false;
#if defined(PETFEEDER_WOKWI_SIMULATION)
struct SimInputs {
  double weight = 0, distance = 12, pulseGrams = 5, lateDrop = 0, noise = 0;
  bool scaleOnline = true, ultrasonicOnline = true, present = true,
       presenceAvailable = true, lid = false;
  int jamAfterPulses = -1;
} sim;
unsigned simPulses = 0;
int previousFeedAngle = 0;
#endif
struct Schedule {
  String id;
  int hour, minute, portion;
  bool enabled;
  int daysMask;
  int lastDay = -1;
};
std::vector<Schedule> schedules;

uint64_t epochNow() {
  time_t t = time(nullptr);
  return t > 1609459200 ? (uint64_t)t : 0;
}
int dayNow() {
  struct tm t;
  return getLocalTime(&t, 0) ? (t.tm_year + 1900) * 1000 + t.tm_yday : -1;
}
#define CONFIG_FIELDS(X)                                                       \
  X("bowl_capacity_g", bowlCapacity)                                           \
  X("max_daily_portion_g", dailyLimit)                                         \
  X("portion_tolerance_g", tolerance)                                          \
  X("fine_threshold_g", fineThreshold) X("stable_spread_g", stableSpread) X(   \
      "idle_delta_g", idleDelta) X("interference_drop_g", interferenceDrop)    \
      X("min_pulse_gain_g", minPulseGain) X("empty_threshold_cm",              \
                                            emptyDistance)                     \
          X("tank_height_cm", hopperHeight) X("refill_jump_cm", refillJump)    \
              X("safe_interval_sec", safeInterval)                             \
                  X("max_duration_ms", maxDuration) X("stable_timeout_ms",     \
                                                      stableTimeout)           \
                      X("coarse_open_ms", coarseOpen) X("coarse_settle_ms",    \
                                                        coarseSettle)          \
                          X("fine_open_ms", fineOpen) X("fine_settle_ms",      \
                                                        fineSettle)            \
                              X("anti_step_ms", antiStep) X("sample_stale_ms", \
                                                            sampleStale)       \
                                  X("max_feed_pulses", maxPulses)              \
                                      X("anti_jam_max_retries", maxRecoveries) \
                                          X("max_daily_feeds", dailyFeeds)

void writeResult(JsonObject obj, const feeder::Result &r) {
  obj["command_id"] = r.command.id;
  obj["source"] = r.command.source;
  obj["command"] = r.command.action;
  obj["retry_of"] = r.command.retryOf;
  obj["root_command_id"] = r.rootId;
  obj["status"] = r.status;
  obj["error_code"] = r.error;
  obj["target_portion_g"] = r.target;
  obj["root_target_g"] = r.rootTarget;
  obj["portion_tolerance_g"] = r.tolerance;
  if (r.measurementValid)
    obj["actual_weight_g"] = r.actual;
  else
    obj["actual_weight_g"] = nullptr;
  obj["last_confirmed_delivered_g"] = r.actual;
  obj["cumulative_delivered_g"] = r.cumulative;
  obj["measurement_valid"] = r.measurementValid;
  obj["last_bowl_weight_g"] = r.bowl;
  obj["started_at"] = r.startedAt;
  obj["completed_at"] = r.completedAt;
  obj["revision"] = r.revision;
  obj["event_id"] = r.eventId();
}
feeder::Result readResult(JsonObject obj) {
  feeder::Result r;
  r.command.id = obj["command_id"].as<std::string>();
  r.command.source = obj["source"].as<std::string>();
  r.command.action = obj["command"].as<std::string>();
  r.command.retryOf = obj["retry_of"].as<std::string>();
  r.rootId = obj["root_command_id"].as<std::string>();
  r.status = obj["status"].as<std::string>();
  r.error = obj["error_code"].as<std::string>();
  r.target = obj["target_portion_g"] | 0.;
  r.command.target = r.target;
  r.rootTarget = obj["root_target_g"] | r.target;
  r.tolerance = obj["portion_tolerance_g"] | 3.;
  r.actual = obj["last_confirmed_delivered_g"] | 0.;
  r.cumulative = obj["cumulative_delivered_g"] | 0.;
  r.measurementValid = obj["measurement_valid"] | false;
  r.bowl = obj["last_bowl_weight_g"] | 0.;
  r.startedAt = obj["started_at"] | (uint64_t)0;
  r.completedAt = obj["completed_at"] | (uint64_t)0;
  r.revision = obj["revision"] | 0;
  return r;
}
bool saveState() {
#if defined(PETFEEDER_WOKWI_SIMULATION)
  // Simulation has a separate namespace and cannot overwrite physical
  // calibration or budgets.
#endif
  if (!nvsReady)
    return false;
  JsonDocument doc;
  doc["version"] = 2;
  doc["day"] = controller.day;
  doc["charged"] = controller.charged;
  doc["count"] = controller.feedCount;
  doc["last_feed"] = controller.lastFeedAt;
  doc["lockdown"] = controller.lockdown;
  doc["verified"] = controller.refillVerified;
  JsonObject cfg = doc["config"].to<JsonObject>();
#define WRITE_CONFIG(key, member) cfg[key] = controller.config.member;
  CONFIG_FIELDS(WRITE_CONFIG)
#undef WRITE_CONFIG
  doc["calibration_factor"] = scaleFactor;
  doc["calibration_offset"] = scaleOffset;
  JsonArray history = doc["recent"].to<JsonArray>();
  // Persist the last 8 physical sessions as well as a pending operation.
  // Rejected floods cannot evict them.
  unsigned count = 0;
  for (auto it = controller.recent.rbegin();
       it != controller.recent.rend() && count < 8; ++it) {
    if (!it->startedAt)
      continue;
    writeResult(history.add<JsonObject>(), *it);
    count++;
  }
  if (controller.busy())
    writeResult(doc["active"].to<JsonObject>(), controller.active);
  String bytes;
  serializeJson(doc, bytes);
  if (bytes.length() > 7000)
    return false;
  return prefs.putBytes("state", bytes.c_str(), bytes.length()) ==
         bytes.length();
}
void enqueue(const String &payload) {
  if (outbox.size() >= 64) {
    Serial.println(
        "[MQTT ERROR] Outbox full; operator reconciliation required");
    controller.lockdown = true;
    return;
  }
  outbox.push_back(payload);
}
void loadState() {
  JsonDocument doc;
  const size_t length = prefs.getBytesLength("state");
  std::vector<char> stored(length + 1, 0);
  if (length)
    prefs.getBytes("state", stored.data(), length);
  if (length && deserializeJson(doc, stored.data(), length)) {
    controller.lockdown = true;
    return;
  }
  controller.day = doc["day"] | -1;
  controller.charged = doc["charged"] | 0.;
  controller.feedCount = doc["count"] | 0;
  controller.lastFeedAt = doc["last_feed"] | (uint64_t)0;
  controller.lockdown = doc["lockdown"] | false;
  controller.refillVerified = doc["verified"] | false;
  feeder::Config next = controller.config;
  JsonObject cfg = doc["config"];
#define LOAD_CONFIG(key, member)                                               \
  if (!cfg[key].isNull())                                                      \
    next.member = cfg[key].as<decltype(next.member)>();
  CONFIG_FIELDS(LOAD_CONFIG)
#undef LOAD_CONFIG
  if (next.valid())
    controller.config = next;
  else
    controller.lockdown = true;
  scaleFactor = doc["calibration_factor"] | 0.;
  scaleOffset = doc["calibration_offset"] | 0.;
  for (JsonObject obj : doc["recent"].as<JsonArray>())
    controller.recent.insert(controller.recent.begin(), readResult(obj));
  if (doc["active"].is<JsonObject>()) {
    auto r = readResult(doc["active"]);
    r.status = "INTERRUPTED";
    r.error = "RESTART_RECONCILIATION_REQUIRED";
    r.measurementValid = false;
    r.revision++;
    controller.lockdown = true;
    bool replaced = false;
    for (auto &prior : controller.recent)
      if (prior.command.id == r.command.id) {
        prior = r;
        replaced = true;
      }
    if (!replaced)
      controller.recent.push_back(r);
    controller.onResult(r);
  }
}
void IRAM_ATTR buttonEdge() {
  const uint32_t now = millis();
  if (digitalRead(PIN_BUTTON) == LOW) {
    if (!buttonDown) {
      buttonDown = true;
      buttonDownAt = now;
    }
  } else if (buttonDown) {
    buttonDown = false;
    buttonDuration = now - buttonDownAt;
    buttonReady = true;
  }
}
feeder::Command localCommand(const char *source, double target = 30) {
  feeder::Command c;
  c.id = (clientId + "_" + String(bootSequence) + "_" + String(++localSequence))
             .c_str();
  c.source = source;
  c.target = target;
  return c;
}
void sampleInputs(uint32_t now) {
  if (now - lastSample >= 50) {
    lastSample = now;
    bool got = false;
    double weight = 0;
#if defined(PETFEEDER_WOKWI_SIMULATION)
    got = sim.scaleOnline;
    weight = sim.weight + ((sampleSequence++ % 2) ? sim.noise : -sim.noise);
    controller.reading.presenceAvailable = sim.presenceAvailable;
    controller.reading.bowlPresent = sim.present;
    controller.reading.lidOpen = sim.lid;
#else
    controller.reading.presenceAvailable = PETFEEDER_BOWL_PRESENT_PIN >= 0;
    controller.reading.bowlPresent =
        PETFEEDER_BOWL_PRESENT_PIN >= 0 &&
        digitalRead(PETFEEDER_BOWL_PRESENT_PIN) == LOW;
    controller.reading.lidOpen =
        PETFEEDER_LID_PIN >= 0 && digitalRead(PETFEEDER_LID_PIN) == HIGH;
    if (scale.is_ready() && std::isfinite(scaleFactor) &&
        std::fabs(scaleFactor) > 0.000001) {
      weight = (scale.read() - scaleOffset) / scaleFactor;
      got = std::isfinite(weight);
    }
#endif
    if (got) {
      lastScaleGood = now;
      controller.reading.weight = weight;
      controller.reading.weightAt = now;
      controller.reading.scale = true;
      samples.push_back(weight);
      if (samples.size() > 5)
        samples.erase(samples.begin());
      controller.reading.stable =
          samples.size() == 5 &&
          *std::max_element(samples.begin(), samples.end()) -
                  *std::min_element(samples.begin(), samples.end()) <=
              controller.config.stableSpread;
    } else {
      samples.clear();
      controller.reading.stable = false;
      if (now - lastScaleGood >= 1000)
        controller.reading.scale = false;
    }
  }
  if (now - lastDistance >= 100) {
    lastDistance = now;
    bool got;
    double distance;
#if defined(PETFEEDER_WOKWI_SIMULATION)
    got = sim.ultrasonicOnline;
    distance = sim.distance;
#else
    digitalWrite(PIN_TRIG, LOW);
    delayMicroseconds(2);
    digitalWrite(PIN_TRIG, HIGH);
    delayMicroseconds(10);
    digitalWrite(PIN_TRIG, LOW);
    const long duration = pulseIn(PIN_ECHO, HIGH, 30000);
    got = duration > 0;
    distance = duration * 0.034 / 2.0;
#endif
    if (got && std::isfinite(distance) && distance >= 0) {
      ultrasonicMisses = 0;
      controller.reading.distance = distance;
      controller.reading.distanceAt = now;
      controller.reading.ultrasonic = true;
    } else if (++ultrasonicMisses >= 3)
      controller.reading.ultrasonic = false;
  }
}
void applyConfig(JsonObject cfg) {
  auto next = controller.config;
  bool numericValid = true, hasNumeric = false;
#define READ_CONFIG(key, member)                                               \
  if (!cfg[key].isNull()) {                                                    \
    hasNumeric = true;                                                         \
    double v = cfg[key].as<double>();                                          \
    if (!cfg[key].is<double>() || !std::isfinite(v) ||                         \
        (std::is_integral<decltype(next.member)>::value &&                     \
         (v < 0 || v > std::numeric_limits<decltype(next.member)>::max() ||    \
          std::floor(v) != v)))                                                \
      numericValid = false;                                                    \
    else                                                                       \
      next.member = cfg[key].as<decltype(next.member)>();                      \
  }
  CONFIG_FIELDS(READ_CONFIG)
#undef READ_CONFIG
  for (const char *key : {"lockdown", "mark_refill", "verify_refill"}) {
    if (!cfg[key].isNull() && !cfg[key].is<bool>()) {
      Serial.println("[CONFIG ERROR] Safety flag must be boolean");
      return;
    }
  }
  if (!numericValid || !next.valid()) {
    Serial.println("[CONFIG ERROR] Invalid config");
    return;
  }
  // A safety lock must still work while the dispensing controller is busy.
  if (!controller.setSafety(cfg["lockdown"] | controller.lockdown,
                            cfg["mark_refill"] | false,
                            cfg["verify_refill"] | false)) {
    Serial.println("[CONFIG ERROR] Persistence failed");
    return;
  }
  if (hasNumeric && !controller.updateConfig(next))
    Serial.println("[CONFIG ERROR] Numeric config rejected while busy");
}
void mqttMessage(char *topic, byte *bytes, unsigned length) {
  JsonDocument doc;
  if (deserializeJson(doc, bytes, length)) {
    Serial.println("[MQTT ERROR] Invalid JSON");
    return;
  }
  if (String(topic) == commandTopic) {
    const String action = doc["command"] | "";
    const std::string id = doc["command_id"].as<std::string>();
    if (action == "QUERY") {
      feeder::Command c;
      c.id = id;
      c.target = doc["target_portion_g"] | 30.;
      c.expiresAt = doc["expires_at"] | (uint64_t)0;
      controller.query(c, epochNow());
      return;
    }
    if (action == "CANCEL") {
      controller.cancel(id, epochNow());
      return;
    }
    feeder::Command c;
    c.id = id;
    c.action = action.c_str();
    c.source = doc["source"] | "app";
    c.retryOf = doc["retry_of"] | "";
    c.overrideInterval = doc["override"] | false;
    c.confirmBowl = doc["confirm_bowl"] | false;
    c.target = doc["target_portion_g"] | (doc["portion"] | 0.);
    c.expiresAt = doc["expires_at"] | (uint64_t)0;
    const bool invalid =
        !doc["target_portion_g"].is<double>() && !doc["portion"].is<double>();
    if (invalid || !c.expiresAt || !doc["expires_at"].is<uint64_t>() ||
        (!doc["target_portion_g"].isNull() &&
         !doc["target_portion_g"].is<double>()) ||
        (!doc["portion"].isNull() && !doc["portion"].is<double>()) ||
        (!doc["confirm_bowl"].isNull() && !doc["confirm_bowl"].is<bool>()) ||
        (!doc["override"].isNull() && !doc["override"].is<bool>()) ||
        (!doc["portion"].isNull() && !doc["target_portion_g"].isNull() &&
         doc["portion"].as<double>() != c.target))
      c.target = 0;
    controller.request(c, millis(), epochNow(), dayNow());
  } else if (String(topic) == configTopic) {
    applyConfig(doc["config"].as<JsonObject>());
  } else if (String(topic) == scheduleTopic) {
    if (!doc["schedules"].is<JsonArray>() || controller.busy())
      return;
    std::vector<Schedule> next;
    for (JsonObject s : doc["schedules"].as<JsonArray>()) {
      if (next.size() >= 10 || !s["id"].is<const char *>() ||
          !s["time"].is<const char *>() || !s["enabled"].is<bool>())
        return;
      Schedule a;
      a.id = s["id"].as<String>();
      a.portion = s["portion"] | 0;
      a.enabled = s["enabled"];
      String t = s["time"].as<String>();
      if (t.length() != 5 || t[2] != ':' || !isDigit(t[0]) || !isDigit(t[1]) ||
          !isDigit(t[3]) || !isDigit(t[4]))
        return;
      a.hour = t.substring(0, 2).toInt();
      a.minute = t.substring(3).toInt();
      if (a.hour > 23 || a.minute > 59 || a.portion < 5 || a.portion > 300)
        return;
      a.daysMask = s["days_mask"] | 127;
      for (auto &old : schedules)
        if (old.id == a.id)
          a.lastDay = old.lastDay;
      next.push_back(a);
    }
    schedules = next;
  }
}
void publishTelemetry() {
  JsonDocument d;
  const auto &r = controller.reading;
  d["contract_version"] = 2;
  d["device_id"] = "petfeeder_01";
  d["status"] = controller.busy() ? controller.active.status : "SAN SANG";
  if (r.scale)
    d["bowl_weight_g"] = r.weight;
  else
    d["bowl_weight_g"] = nullptr;
  if (r.ultrasonic) {
    d["distance_cm"] = r.distance;
    d["food_level_percent"] =
        constrain((int)((controller.config.hopperHeight - r.distance) /
                        controller.config.hopperHeight * 100),
                  0, 100);
  } else {
    d["distance_cm"] = nullptr;
    d["food_level_percent"] = nullptr;
  }
  d["lid_open"] = r.lidOpen;
  d["scale_valid"] = r.scale;
  d["scale_stable"] = r.stable;
  d["ultrasonic_valid"] = r.ultrasonic;
  d["bowl_presence_available"] = r.presenceAvailable;
  if (r.presenceAvailable)
    d["bowl_present"] = r.bowlPresent;
  else
    d["bowl_present"] = nullptr;
  d["food_quality_status"] = "UNVERIFIED";
  d["hopper_verified"] = controller.refillVerified;
  d["lockdown"] = controller.lockdown;
  d["busy"] = controller.busy();
  d["active_command_id"] =
      controller.busy() ? controller.active.command.id : "";
  d["daily_charged_g"] = controller.charged;
  d["daily_feed_count"] = controller.feedCount;
#if defined(PETFEEDER_WOKWI_SIMULATION)
  d["simulation_mode"] = true;
#else
  d["simulation_mode"] = false;
#endif
  JsonObject snapshot = d["config_snapshot"].to<JsonObject>();
#define TELEMETRY_CONFIG(key, member) snapshot[key] = controller.config.member;
  CONFIG_FIELDS(TELEMETRY_CONFIG)
#undef TELEMETRY_CONFIG
  snapshot["lockdown"] = controller.lockdown;
  String payload;
  serializeJson(d, payload);
  if (mqtt.publish(telemetryTopic.c_str(), payload.c_str(), false))
    Serial.printf("[MQTT OUT] Telemetry: %u bytes\n", payload.length());
  else
    Serial.printf("[MQTT ERROR] Telemetry failed, state=%d\n", mqtt.state());
}
void serialControl() {
  while (Serial.available()) {
    const char c = Serial.read();
    if (c != '\n' && c != '\r') {
      if (serialLine.length() < 1024)
        serialLine += c;
      else
        serialLine = "";
      continue;
    }
    if (!serialLine.length())
      continue;
    JsonDocument d;
    auto err = deserializeJson(d, serialLine);
    serialLine = "";
    if (err) {
      Serial.println("[SERIAL ERROR] Expected JSON line");
      continue;
    }
#if defined(PETFEEDER_WOKWI_SIMULATION)
    JsonObject s = d["sim"];
    if (!s.isNull()) {
      if (!s["weight_g"].isNull())
        sim.weight = s["weight_g"];
      if (!s["distance_cm"].isNull())
        sim.distance = s["distance_cm"];
      if (!s["pulse_g"].isNull())
        sim.pulseGrams = s["pulse_g"];
      if (!s["late_drop_g"].isNull())
        sim.lateDrop = s["late_drop_g"];
      if (!s["noise_g"].isNull())
        sim.noise = s["noise_g"];
      if (!s["scale_online"].isNull())
        sim.scaleOnline = s["scale_online"];
      if (!s["ultrasonic_online"].isNull())
        sim.ultrasonicOnline = s["ultrasonic_online"];
      if (!s["bowl_present"].isNull())
        sim.present = s["bowl_present"];
      if (!s["presence_available"].isNull())
        sim.presenceAvailable = s["presence_available"];
      if (!s["lid_open"].isNull())
        sim.lid = s["lid_open"];
      if (!s["jam_after_pulses"].isNull()) {
        sim.jamAfterPulses = s["jam_after_pulses"];
        simPulses = 0;
      }
      Serial.println("[SIM] Inputs changed (simulation only)");
    }
#endif
    if (d["calibration"].is<JsonObject>() && !controller.busy()) {
      JsonObject c = d["calibration"];
      const double factor = c["factor"] | scaleFactor,
                   offset = c["offset"] | scaleOffset;
      if (std::isfinite(factor) && std::fabs(factor) > 0.000001 &&
          std::isfinite(offset)) {
        scaleFactor = factor;
        scaleOffset = offset;
        saveState();
        Serial.println(
            "[CALIBRATION] Stored grams factor/offset; no automatic tare");
      }
    }
    if (d["config"].is<JsonObject>())
      applyConfig(d["config"]);
    if (d["feed_g"].is<double>())
      controller.request(localCommand("button", d["feed_g"]), millis(),
                         epochNow(), dayNow());
  }
}
void setup() {
  Serial.begin(115200);
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  pinMode(PIN_TRIG, OUTPUT);
  pinMode(PIN_ECHO, INPUT);
  pinMode(PIN_LED_GREEN, OUTPUT);
  pinMode(PIN_LED_RED, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);
  if (PETFEEDER_BOWL_PRESENT_PIN >= 0)
    pinMode(PETFEEDER_BOWL_PRESENT_PIN, INPUT_PULLUP);
  if (PETFEEDER_LID_PIN >= 0)
    pinMode(PETFEEDER_LID_PIN, INPUT_PULLUP);
  feedServo.attach(PIN_SERVO_FEED);
  antiServo.attach(PIN_SERVO_ANTI);
  feedServo.write(0);
  antiServo.write(90);
  scale.begin(PIN_HX711_DT, PIN_HX711_SCK); // Never tare food away at boot.
  oledReady = display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
#if defined(PETFEEDER_WOKWI_SIMULATION)
  nvsReady = prefs.begin("feeder-sim-v2", false);
#else
  nvsReady = prefs.begin("feeder-real-v2", false);
#endif
  bootSequence = prefs.getUInt("boot", 0) + 1;
  prefs.putUInt("boot", bootSequence);
  clientId = String("PetFeeder_") + String((uint32_t)ESP.getEfuseMac(), HEX);
  controller.onResult = [](const feeder::Result &r) {
    JsonDocument d;
    auto obj = d.to<JsonObject>();
    writeResult(obj, r);
    obj["event"] = "FEED_RESULT";
    obj["contract_version"] = 2;
    String json;
    serializeJson(d, json);
    enqueue(json);
    Serial.printf("[FEED RESULT] %s\n", json.c_str());
  };
  controller.onBowl = [](const std::string &type, double delta, double weight,
                         const std::string &cause) {
    JsonDocument d;
    d["event"] = "BOWL_EVENT";
    d["type"] = type;
    d["delta_g"] = delta;
    d["current_bowl_weight_g"] = weight;
    d["cause"] = cause;
    d["timestamp"] = epochNow();
    d["event_id"] = clientId + "_" + String(bootSequence) + "_bowl_" +
                    String(++bowlSequence);
    String json;
    serializeJson(d, json);
    enqueue(json);
    Serial.printf("[BOWL EVENT] %s\n", json.c_str());
  };
  loadState();
  controller.persist = saveState;
  if (!saveState())
    controller.lockdown = true;
  attachInterrupt(digitalPinToInterrupt(PIN_BUTTON), buttonEdge, CHANGE);
  WiFi.begin("Wokwi-GUEST", "");
  configTime(7 * 3600, 0, "pool.ntp.org", "time.google.com");
  mqtt.setServer("broker.emqx.io", 1883);
  mqtt.setCallback(mqttMessage);
  mqtt.setBufferSize(4096);
  mqtt.setKeepAlive(60);
  mqtt.setSocketTimeout(1);
  Serial.println("[BOOT] Contract v2. Refill requires owner acknowledgement. "
                 "JSON Serial controls enabled.");
}
void loop() {
  uint32_t now = millis();
  serialControl();
  sampleInputs(now);
  if (WiFi.status() == WL_CONNECTED) {
    if (!mqtt.connected() &&
        (!controller.busy() || controller.phase == feeder::Phase::Paused) &&
        now - lastConnect >= 4000) {
      lastConnect = now;
      if (mqtt.connect(clientId.c_str())) {
        mqtt.subscribe(commandTopic.c_str());
        mqtt.subscribe(configTopic.c_str());
        mqtt.subscribe(scheduleTopic.c_str());
        Serial.println("[MQTT] Connected (contract v2)");
      } else
        Serial.printf("[MQTT] Connect failed: %d\n", mqtt.state());
    }
    if (mqtt.connected())
      mqtt.loop();
  }
  if (buttonReady) {
    noInterrupts();
    uint32_t duration = buttonDuration;
    buttonReady = false;
    interrupts();
    if (duration >= 2500 && !controller.refillVerified)
      controller.setSafety(controller.lockdown, false, true);
    else if (duration >= 50) {
      auto c = localCommand("button");
      c.overrideInterval = duration >= 2500;
      controller.request(c, now, epochNow(), dayNow());
    }
  }
  struct tm local;
  if (getLocalTime(&local, 0)) {
    for (auto &s : schedules)
      if (s.enabled && s.lastDay != dayNow() &&
          (s.daysMask & (1 << local.tm_wday)) && s.hour == local.tm_hour &&
          s.minute == local.tm_min) {
        s.lastDay = dayNow();
        auto c = localCommand("schedule", s.portion);
        c.id = (String("schedule_") + s.id + "_" + String(s.lastDay)).c_str();
        controller.request(c, now, epochNow(), dayNow());
      }
  }
  controller.tick(now, epochNow());
#if defined(PETFEEDER_WOKWI_SIMULATION)
  if (previousFeedAngle > 0 && previousFeedAngle != 120 &&
      controller.feedAngle == 0) {
    simPulses++;
    if (sim.jamAfterPulses < 0 || (int)simPulses <= sim.jamAfterPulses) {
      const double amount = previousFeedAngle == 60
                                ? std::min(2.5, sim.pulseGrams)
                                : sim.pulseGrams;
      sim.weight += amount + sim.lateDrop; // Deliberately permit overrun and
                                           // under-delivery for tests.
    }
  }
  previousFeedAngle = controller.feedAngle;
#endif
  feedServo.write(controller.feedAngle);
  antiServo.write(controller.antiAngle);
  digitalWrite(PIN_LED_GREEN,
               controller.busy() && controller.phase != feeder::Phase::Paused);
  digitalWrite(PIN_LED_RED, controller.lockdown || !controller.refillVerified ||
                                controller.phase == feeder::Phase::Paused);
  // Audible attention is scheduled, never a blocking beep loop.
  digitalWrite(PIN_BUZZER,
               controller.phase == feeder::Phase::Paused && now % 1000 < 100);
  if (mqtt.connected() && !outbox.empty() &&
      mqtt.publish(eventTopic.c_str(), outbox.front().c_str(), false))
    outbox.pop_front();
  if (mqtt.connected() && now - lastTelemetry >= 1000) {
    lastTelemetry = now;
    publishTelemetry();
  }
  if (oledReady && now - lastScreen >= 500) {
    lastScreen = now;
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 0);
    display.println("PETFEEDER v2");
#if defined(PETFEEDER_WOKWI_SIMULATION)
    display.println("SIMULATION");
#endif
    if (controller.reading.scale)
      display.printf("Bat: %.1f g\n", controller.reading.weight);
    else
      display.println("Bat: LOI CAN");
    if (controller.reading.ultrasonic)
      display.printf("Hop: %.1f cm\n", controller.reading.distance);
    else
      display.println("Hop: LOI CB");
    display.println(controller.busy() ? controller.active.status.c_str()
                                      : "SAN SANG");
    if (controller.lockdown)
      display.println("KHOA AN TOAN");
    else if (!controller.refillVerified)
      display.println("CHO XAC NHAN HAT");
    else if (!controller.reading.presenceAvailable)
      display.println("THIEU CAM BIEN BAT");
    display.display();
  }
  delay(2); // Yield between bounded sensor/controller steps.
}
