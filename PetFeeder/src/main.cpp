#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <ESP32Servo.h>
#include "HX711.h"
#include <time.h>

// ===================== CẤU HÌNH PHẦN CỨNG & CHÂN (PIN MAPPING) =====================
#define PIN_TRIG        5
#define PIN_ECHO        18
#define PIN_HX711_DT    19
#define PIN_HX711_SCK   23
#define PIN_BUTTON      4
#define PIN_SERVO_FEED  13
#define PIN_SERVO_ANTI  12
#define PIN_LED_GREEN   2
#define PIN_LED_RED     15
#define PIN_BUZZER      14

// OLED 0.96 inch SSD1306 I2C (SDA = GPIO 21, SCL = GPIO 22)
#define SCREEN_WIDTH    128
#define SCREEN_HEIGHT   64
#define OLED_RESET      -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

Servo servoFeed;
Servo servoAnti;
HX711 scale;

// Thông số bồn chứa & cảm biến
const float HOP_CHUA_CAO_CM   = 25.0;  // Chiều cao tối đa của hộp chứa
const float NGUONG_HET_HAT_CM = 20.0;  // Khoảng cách tới hạt >= 20cm là hết hạt

#if defined(PETFEEDER_WOKWI_SIMULATION)
// Wokwi không tự thay đổi HC-SR04/HX711 khi servo quay. Mô phỏng một hộp
// 500g đang có khoảng 52% hạt (khớp distance 12cm trong diagram.json).
const float SIM_HOPPER_CAPACITY_G = 500.0;
const float SIM_INITIAL_HOPPER_G  = 500.0;
const float SIM_PULSE_GRAMS       = 5.0;
float simulatedHopperGrams        = SIM_INITIAL_HOPPER_G;
float simulatedBowlWeightGrams    = 0.0;
#endif

// ===================== CẤU HÌNH MẠNG & MQTT =====================
// Mô phỏng Wokwi dùng WiFi ảo "Wokwi-GUEST", không mật khẩu
const char* WIFI_SSID     = "Wokwi-GUEST";
const char* WIFI_PASSWORD = "";

// Public MQTT broker dùng chung cho Wokwi Community và backend.
// Đổi sang broker riêng có authentication khi triển khai production.
#define MQTT_SERVER       "broker.emqx.io"
#define MQTT_PORT         1883
#define MQTT_CLIENT_ID    "ESP32_PetFeeder_Client"
#define MQTT_TOPIC_PREFIX "duylinh0212/petfeeder/v1"

// MQTT Topics
const char* TOPIC_COMMAND   = MQTT_TOPIC_PREFIX "/command";
const char* TOPIC_SCHEDULES = MQTT_TOPIC_PREFIX "/schedules/sync";
const char* TOPIC_CONFIG    = MQTT_TOPIC_PREFIX "/config";
const char* TOPIC_TELEMETRY = MQTT_TOPIC_PREFIX "/telemetry";
const char* TOPIC_EVENTS    = MQTT_TOPIC_PREFIX "/events";
const char* TOPIC_ALERTS    = MQTT_TOPIC_PREFIX "/alerts";

WiFiClient espClient;
PubSubClient mqttClient(espClient);
String mqttClientId = MQTT_CLIENT_ID;

// ===================== QUẢN LÝ LỊCH CỤC BỘ (FR-04) =====================
struct LocalSchedule {
  char id[20];
  int hour;
  int minute;
  int portion;
  bool enabled;
  int lastTriggerDay;
};

#define MAX_SCHEDULES 10
LocalSchedule localSchedules[MAX_SCHEDULES];
int scheduleCount = 0;

// ===================== BIẾN TRẠNG THÁI & CHỐNG ĂN TRÙNG =====================
unsigned long lastFeedSuccessMs = 0;
unsigned long safeIntervalMs    = 180000; // Mặc định 180s (3 phút) theo Section 2.3.2
String systemStatus             = "KHOI DONG";

// Nút bấm
unsigned long buttonPressTime = 0;
bool isButtonPressed         = false;

// Chu kỳ cập nhật
unsigned long lastDisplayUpdate   = 0;
unsigned long lastTelemetryUpdate = 0;
unsigned long lastMQTTReconnect   = 0;

// Nguyên mẫu hàm
void beep(int count, int delayMs);
float readDistanceCM();
float readWeightGram();
void updateOLED(float distance, float weight, String status);
void triggerAntiJam();
bool performFeeding(int targetPortion, bool isOverride, String source);
void setupWiFi();
void reconnectMQTT();
void mqttCallback(char* topic, byte* message, unsigned int length);
void publishTelemetry();
void publishFeedEvent(String status, String source, int targetPortion, float actualWeight, String message);
void checkLocalSchedules();

// ===================== ÂM THANH BUZZER =====================
void beep(int count, int delayMs) {
  for (int i = 0; i < count; i++) {
    digitalWrite(PIN_BUZZER, HIGH);
    delay(delayMs);
    digitalWrite(PIN_BUZZER, LOW);
    if (i < count - 1) delay(delayMs);
  }
}

// ===================== ĐỌC CẢM BIẾN =====================
float readDistanceCM() {
#if defined(PETFEEDER_WOKWI_SIMULATION)
  float level = constrain(simulatedHopperGrams / SIM_HOPPER_CAPACITY_G, 0.0, 1.0);
  return HOP_CHUA_CAO_CM * (1.0 - level);
#else
  digitalWrite(PIN_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);
  
  long duration = pulseIn(PIN_ECHO, HIGH, 30000);
  if (duration == 0) return HOP_CHUA_CAO_CM;
  float dist = duration * 0.034 / 2.0;
  return constrain(dist, 2.0, HOP_CHUA_CAO_CM);
#endif
}

float readWeightGram() {
#if defined(PETFEEDER_WOKWI_SIMULATION)
  return simulatedBowlWeightGrams;
#else
  if (scale.is_ready()) {
    long reading = scale.get_units(2);
    float weight = (float)reading / 420.0;
    if (weight < 0.0) weight = 0.0;
    return weight;
  }
  return 0.0;
#endif
}

#if defined(PETFEEDER_WOKWI_SIMULATION)
void simulateDispensePulse(int targetPortion, float initialWeight, float currentWeight) {
  float delivered = currentWeight - initialWeight;
  float remaining = targetPortion - delivered;
  if (remaining <= 0.0 || simulatedHopperGrams <= 0.0) return;

  float dispensed = min(SIM_PULSE_GRAMS, min(remaining, simulatedHopperGrams));
  simulatedHopperGrams -= dispensed;
  simulatedBowlWeightGrams += dispensed;

  Serial.printf("[SIM] Da mo phong %.1fg | Kho con: %.1fg | Bat: %.1fg\n",
                dispensed, simulatedHopperGrams, simulatedBowlWeightGrams);
}
#endif

// ===================== MÀN HÌNH OLED =====================
void updateOLED(float distance, float weight, String status) {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextWrap(false);

  // Header
  display.setTextSize(1);
  display.setCursor(10, 0);
  display.print("PET FEEDER - IOT");
  
  // Icon Wi-Fi & MQTT
  if (WiFi.status() == WL_CONNECTED) {
    display.setCursor(116, 0);
    display.print(mqttClient.connected() ? "M" : "W");
  }
  display.drawLine(0, 9, 128, 9, SSD1306_WHITE);

  // Mức hạt
  display.setCursor(0, 13);
  display.print("Hat: ");
  if (distance >= NGUONG_HET_HAT_CM) {
    display.print("HET HAT");
  } else {
    int percent = constrain((int)((HOP_CHUA_CAO_CM - distance) / HOP_CHUA_CAO_CM * 100), 0, 100);
    display.print(percent);
    display.print("% ");
    display.print((int)distance);
    display.print("cm");
  }

  // Khối lượng bát
  display.setCursor(0, 26);
  display.print("Bat: ");
  display.print(weight, 1);
  display.print(" g");

  // Trạng thái hệ thống
  display.setCursor(0, 39);
  display.print("TT: ");
  if (status.length() > 15) status = status.substring(0, 15);
  display.print(status);

  // Hướng dẫn thao tác tại chỗ
  display.drawLine(0, 52, 128, 52, SSD1306_WHITE);
  display.setCursor(0, 55);
  display.print("Nhan=AN  Giu=OVR");

  display.display();
}

// ===================== CƠ CẤU CHỐNG KẸT (ANTI-JAM RECOVERY) =====================
void triggerAntiJam() {
  Serial.println("[ANTI-JAM] Phat hien nghi ket hat! Kich hoat co cau tu phuc hoi...");
  systemStatus = "XU LY KET!";
  updateOLED(readDistanceCM(), readWeightGram(), systemStatus);
  
  digitalWrite(PIN_LED_RED, HIGH);
  beep(3, 80);

  // Đảo chiều Servo chính (Section 2.3.3)
  servoFeed.write(120);
  delay(200);

  // Lắc cơ cấu chống kẹt phụ 3 lần liên tiếp (Section 2.3.3)
  for (int i = 0; i < 3; i++) {
    servoAnti.write(45);
    delay(150);
    servoAnti.write(135);
    delay(150);
  }
  servoAnti.write(90);
  servoFeed.write(0);
  
  digitalWrite(PIN_LED_RED, LOW);
}

// ===================== LUỒNG CẤP THỨC ĂN (FEEDING CONTROLLER) =====================
bool performFeeding(int targetPortion, bool isOverride, String source) {
  unsigned long now = millis();
  float distance = readDistanceCM();
  float initialWeight = readWeightGram();

  Serial.printf("\n>>> [FEED REQUEST] Nguon: %s | Khau phan: %dg | Override: %s\n",
                source.c_str(), targetPortion, isOverride ? "YES" : "NO");

  // Bước 2: Kiểm tra chống cho ăn trùng (Section 2.3.2)
  if (!isOverride && lastFeedSuccessMs > 0 && (now - lastFeedSuccessMs < safeIntervalMs)) {
    unsigned long elapsedSec = (now - lastFeedSuccessMs) / 1000;
    Serial.printf("[BLOCKED] Cho an cach day %ds (nguong %ds). Bi chan!\n", elapsedSec, safeIntervalMs / 1000);
    
    systemStatus = "BLOCKED - VUA AN";
    updateOLED(distance, initialWeight, systemStatus);
    
    // Phản hồi tại chỗ: LED Đỏ chớp 2 lần, Buzzer bíp 2 tiếng (Section 2.3.2)
    for (int i = 0; i < 2; i++) {
      digitalWrite(PIN_LED_RED, HIGH);
      digitalWrite(PIN_BUZZER, HIGH);
      delay(100);
      digitalWrite(PIN_LED_RED, LOW);
      digitalWrite(PIN_BUZZER, LOW);
      delay(100);
    }

    publishFeedEvent("BLOCKED", source, targetPortion, 0, "Lenh bi chan do vua moi cho an!");
    delay(1500);
    systemStatus = "SAN SANG";
    return false;
  }

  // Bước 3: Kiểm tra mức thức ăn trong hộp (Section 2.3.1)
  if (distance >= NGUONG_HET_HAT_CM && !isOverride) {
    Serial.println("[EMPTY] Hop chua da het hat!");
    systemStatus = "LOI: HET HAT";
    updateOLED(distance, initialWeight, systemStatus);

    digitalWrite(PIN_LED_RED, HIGH);
    beep(4, 150);
    digitalWrite(PIN_LED_RED, LOW);

    publishFeedEvent("EMPTY", source, targetPortion, 0, "Hop chua het thuc an!");
    delay(1500);
    systemStatus = "SAN SANG";
    return false;
  }

  // Bước 4: Cấp thức ăn định lượng vòng kín (Closed-Loop Section 2.1.4)
  systemStatus = isOverride ? "OVERRIDE FEED" : "DANG CHO AN...";
  digitalWrite(PIN_LED_GREEN, HIGH);
  updateOLED(distance, initialWeight, systemStatus);
  beep(1, 150);

  int jamSuspectCount = 0;
  const int MAX_JAM_RETRIES = 3;
  float currentWeight = initialWeight;
  int pulses = 0;
  const int MAX_PULSES = 20;

  while ((currentWeight - initialWeight) < (float)targetPortion && pulses < MAX_PULSES) {
    pulses++;
    float weightBeforePulse = currentWeight;

    // Nhịp xoay nhả hạt
    servoFeed.write(90);
    delay(500);
    servoFeed.write(0);
    delay(400);

#if defined(PETFEEDER_WOKWI_SIMULATION)
    simulateDispensePulse(targetPortion, initialWeight, currentWeight);
#endif
    currentWeight = readWeightGram();
    float pulseGain = currentWeight - weightBeforePulse;
    Serial.printf("[PULSE %d] Can nang: %.1fg (+%.1fg)\n", pulses, currentWeight, pulseGain);

    // Cập nhật ngay sau mỗi xung để Mobile/backend thấy mức hạt giảm theo thời gian thực.
    publishTelemetry();

    // Kiểm tra kẹt hạt: khối lượng không tăng đáng kể (Section 2.3.3)
    if (pulseGain < 1.0) {
      jamSuspectCount++;
      Serial.printf("[CANH BAO] Tang khoi luong thap (<1g). Lan nghi ket: %d/%d\n", jamSuspectCount, MAX_JAM_RETRIES);
      
      triggerAntiJam();

      if (jamSuspectCount >= MAX_JAM_RETRIES) {
        // Chuyển sang JAM ERROR nghiêm trọng
        systemStatus = "LOI KET HAT";
        updateOLED(distance, currentWeight, systemStatus);
        digitalWrite(PIN_LED_GREEN, LOW);
        digitalWrite(PIN_LED_RED, HIGH);
        
        // Còi báo lỗi kéo dài
        beep(5, 200);

        float actualDispensed = currentWeight - initialWeight;
        publishFeedEvent("JAM_ERROR", source, targetPortion, actualDispensed, "Co cau bi ket hat! Khong the cap them.");
        delay(2000);
        digitalWrite(PIN_LED_RED, LOW);
        systemStatus = "SAN SANG";
        return false;
      }
    } else {
      jamSuspectCount = 0; // Đã ra hạt bình thường, reset nghi kẹt
    }

    updateOLED(distance, currentWeight, systemStatus);
  }

  // Bước 6: Kết thúc thành công
  float totalDispensed = currentWeight - initialWeight;
  if (totalDispensed < 0) totalDispensed = 0;

  digitalWrite(PIN_LED_GREEN, LOW);
  systemStatus = "HOAN TAT!";
  lastFeedSuccessMs = millis();
  beep(2, 100);

  updateOLED(readDistanceCM(), currentWeight, systemStatus);
  Serial.printf("[THANH CONG] Da cap: %.1fg / Muc tieu: %dg\n", totalDispensed, targetPortion);

  publishFeedEvent("SUCCESS", source, targetPortion, totalDispensed, "Cho an thanh cong!");
  publishTelemetry();
  delay(1500);
  systemStatus = "SAN SANG";
  return true;
}

// ===================== KẾT NỐI WIFI =====================
void setupWiFi() {
  Serial.printf("\n[WiFi] Dang ket noi toi SSID: %s\n", WIFI_SSID);
  systemStatus = "KET NOI WIFI...";
  updateOLED(readDistanceCM(), readWeightGram(), systemStatus);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[WiFi] Da ket noi thanh cong!");
    Serial.print("[WiFi] IP: ");
    Serial.println(WiFi.localIP());

    // Cấu hình đồng bộ thời gian SNTP qua mạng (UTC+7 cho Việt Nam)
    configTime(7 * 3600, 0, "pool.ntp.org", "time.google.com");
  } else {
    Serial.println("\n[WiFi] Khong the ket noi Wi-Fi! Chay che do ngoai tuyen (FR-04)");
  }
}

// ===================== KẾT NỐI MQTT =====================
void reconnectMQTT() {
  if (mqttClient.connected() || WiFi.status() != WL_CONNECTED) return;

  unsigned long now = millis();
  if (now - lastMQTTReconnect < 4000) return; // Thử lại mỗi 4s
  lastMQTTReconnect = now;

  Serial.printf("[MQTT] Dang ket noi toi Broker: %s:%d...\n", MQTT_SERVER, MQTT_PORT);
  if (mqttClient.connect(mqttClientId.c_str())) {
    Serial.println("[MQTT] Da ket noi thanh cong!");

    // Subscribe các topic điều khiển
    mqttClient.subscribe(TOPIC_COMMAND);
    mqttClient.subscribe(TOPIC_SCHEDULES);
    mqttClient.subscribe(TOPIC_CONFIG);

    Serial.println("[MQTT] Da dang ky cac topic nhan lenh");
    beep(1, 80);
  } else {
    Serial.printf("[MQTT] Ket noi that bai, ma loi rc=%d\n", mqttClient.state());
  }
}

// ===================== XỬ LÝ MESSAGE TỪ BACKEND QUA MQTT =====================
void mqttCallback(char* topic, byte* message, unsigned int length) {
  String payload = "";
  for (unsigned int i = 0; i < length; i++) {
    payload += (char)message[i];
  }
  Serial.printf("\n[MQTT IN] Topic: %s | Payload: %s\n", topic, payload.c_str());

  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, payload);
  if (err) {
    Serial.printf("[MQTT Error] JSON khong hop le: %s\n", err.c_str());
    return;
  }

  // 1. Nhận lệnh cho ăn ngay (FR-08)
  if (String(topic) == TOPIC_COMMAND) {
    String cmd = doc["command"] | "";
    if (cmd == "FEED") {
      int portion = doc["portion"] | 30;
      bool override = doc["override"] | false;
      String src = doc["source"] | "app";
      performFeeding(portion, override, src);
    }
  }

  // 2. Nhận đồng bộ lịch từ Backend (FR-04)
  else if (String(topic) == TOPIC_SCHEDULES) {
    JsonArray arr = doc["schedules"].as<JsonArray>();
    scheduleCount = 0;
    for (JsonObject obj : arr) {
      if (scheduleCount >= MAX_SCHEDULES) break;
      const char* t = obj["time"] | "00:00";
      int p = obj["portion"] | 30;
      bool en = obj["enabled"] | true;
      const char* id = obj["id"] | "";

      int h = 0, m = 0;
      sscanf(t, "%d:%d", &h, &m);

      strncpy(localSchedules[scheduleCount].id, id, sizeof(localSchedules[scheduleCount].id));
      localSchedules[scheduleCount].hour = h;
      localSchedules[scheduleCount].minute = m;
      localSchedules[scheduleCount].portion = p;
      localSchedules[scheduleCount].enabled = en;
      localSchedules[scheduleCount].lastTriggerDay = -1;
      scheduleCount++;
    }
    Serial.printf("[SCHEDULES] Da dong bo %d lich cho an cuc bo!\n", scheduleCount);
  }

  // 3. Nhận cấu hình thiết bị
  else if (String(topic) == TOPIC_CONFIG) {
    if (doc["config"]["safe_interval_sec"]) {
      safeIntervalMs = (unsigned long)doc["config"]["safe_interval_sec"] * 1000;
      Serial.printf("[CONFIG] Cap nhat nguong an toan safeIntervalMs = %lu\n", safeIntervalMs);
    }
  }
}

// ===================== GỬI TELEMETRY =====================
void publishTelemetry() {
  if (!mqttClient.connected()) return;

  float dist = readDistanceCM();
  float weight = readWeightGram();
  int percent = constrain((int)((HOP_CHUA_CAO_CM - dist) / HOP_CHUA_CAO_CM * 100), 0, 100);

  JsonDocument doc;
  doc["device_id"]          = "petfeeder_01";
  doc["distance_cm"]        = round(dist * 10) / 10.0;
  doc["food_level_percent"] = percent;
  doc["bowl_weight_g"]      = round(weight * 10) / 10.0;
  doc["status"]             = systemStatus;
  doc["ip"]                 = WiFi.localIP().toString();
  doc["rssi"]               = WiFi.RSSI();
  doc["uptime"]             = millis() / 1000;

  char buffer[256];
  serializeJson(doc, buffer);
  // Retain bản mới nhất để backend nhận lại ngay sau khi reconnect.
  mqttClient.publish(TOPIC_TELEMETRY, buffer, true);
}

// ===================== GỬI SỰ KIỆN CHO ĂN (FEED EVENT) =====================
void publishFeedEvent(String status, String source, int targetPortion, float actualWeight, String message) {
  if (!mqttClient.connected()) {
    Serial.println("[MQTT] Ngoai tuyen: khong the gui feed event truc tiep");
    return;
  }

  JsonDocument doc;
  doc["event"]          = "FEED_RESULT";
  doc["status"]         = status;
  doc["trigger_source"] = source;
  doc["target_portion"] = targetPortion;
  doc["actual_weight"]  = round(actualWeight * 10) / 10.0;
  doc["message"]        = message;
  doc["timestamp"]      = (unsigned long)time(nullptr);

  char buffer[256];
  serializeJson(doc, buffer);
  mqttClient.publish(TOPIC_EVENTS, buffer, true);
  Serial.printf("[MQTT OUT] Da publish event: %s\n", buffer);
}

// ===================== KIỂM TRA LỊCH CỤC BỘ (OFFLINE SCHEDULE - FR-04) =====================
void checkLocalSchedules() {
  struct tm timeinfo;
  if (!getLocalTime(&timeinfo)) return;

  int currentHour = timeinfo.tm_hour;
  int currentMin  = timeinfo.tm_min;
  int currentDay  = timeinfo.tm_yday;

  for (int i = 0; i < scheduleCount; i++) {
    if (localSchedules[i].enabled) {
      if (localSchedules[i].hour == currentHour && localSchedules[i].minute == currentMin) {
        if (localSchedules[i].lastTriggerDay != currentDay) {
          localSchedules[i].lastTriggerDay = currentDay;
          Serial.printf("\n[AUTO SCHEDULE] Kich hoat lich cho an: %02d:%02d (%dg)\n",
                        currentHour, currentMin, localSchedules[i].portion);
          performFeeding(localSchedules[i].portion, false, "schedule");
        }
      }
    }
  }
}

// ===================== KHỞI TẠO HỆ THỐNG (SETUP) =====================
void setup() {
  Serial.begin(115200);
  Serial.println("\n=============================================");
  Serial.println("  HE THONG CHO THU CUNG AN TU DONG - NHOM 7  ");
  Serial.println("=============================================");

  // Tránh hai phiên Wokwi dùng chung client ID làm broker đá mất kết nối.
  uint64_t chipId = ESP.getEfuseMac();
  mqttClientId = String(MQTT_CLIENT_ID) + "_" +
                 String((uint32_t)(chipId >> 32), HEX) +
                 String((uint32_t)chipId, HEX);
  Serial.printf("[MQTT] Client ID: %s\n", mqttClientId.c_str());

  pinMode(PIN_TRIG, OUTPUT);
  pinMode(PIN_ECHO, INPUT);
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  pinMode(PIN_LED_GREEN, OUTPUT);
  pinMode(PIN_LED_RED, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);

  digitalWrite(PIN_LED_GREEN, LOW);
  digitalWrite(PIN_LED_RED, LOW);
  digitalWrite(PIN_BUZZER, LOW);

  // Gắn servo
  servoFeed.attach(PIN_SERVO_FEED);
  servoAnti.attach(PIN_SERVO_ANTI);
  servoFeed.write(0);
  servoAnti.write(90);

  // Màn hình OLED
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("[LOI] Khong the tim thay man hinh OLED SSD1306!");
  }
  display.clearDisplay();

  // Cảm biến cân nặng HX711
  scale.begin(PIN_HX711_DT, PIN_HX711_SCK);
  scale.set_scale();
  scale.tare();

  beep(1, 150);
  systemStatus = "KHOI DONG";
  updateOLED(readDistanceCM(), readWeightGram(), systemStatus);

  // Khởi tạo mạng & MQTT
  setupWiFi();
  mqttClient.setServer(MQTT_SERVER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);

  systemStatus = "SAN SANG";
  updateOLED(readDistanceCM(), readWeightGram(), systemStatus);
}

// ===================== VÒNG LẶP CHÍNH (LOOP) =====================
void loop() {
  // 1. Quản lý kết nối MQTT
  if (WiFi.status() == WL_CONNECTED) {
    if (!mqttClient.connected()) {
      reconnectMQTT();
    } else {
      mqttClient.loop();
    }
  }

  // 2. Xử lý nút bấm vật lý (Section 2.3.1 & 2.3.2)
  int btnState = digitalRead(PIN_BUTTON);
  if (btnState == LOW) {
    if (!isButtonPressed) {
      isButtonPressed = true;
      buttonPressTime = millis();
    }
  } else {
    if (isButtonPressed) {
      unsigned long duration = millis() - buttonPressTime;
      isButtonPressed = false;
      
      // Giữ > 2.5s: Override feed (bỏ qua lọc trùng và cảnh báo hết hạt)
      if (duration >= 2500) {
        Serial.println("[BUTTON] Phat hien nhan giu >2.5s: Kich hoat OVERRIDE FEED!");
        beep(1, 400); // 1 tiếng bíp dài xác nhận override
        performFeeding(30, true, "override");
      } 
      // Nhấn nhả < 2.5s: Cho ăn thông thường an toàn
      else if (duration >= 50) {
        Serial.println("[BUTTON] Phat hien nhan nha: Kich hoat cho an tai cho!");
        performFeeding(30, false, "button");
      }
    }
  }

  // 3. Kiểm tra lịch cho ăn tự động (FR-03 & FR-04)
  static unsigned long lastScheduleCheck = 0;
  if (millis() - lastScheduleCheck >= 1000) {
    lastScheduleCheck = millis();
    checkLocalSchedules();
  }

  // 4. Định kỳ gửi Telemetry qua MQTT (mỗi 3 giây)
  if (millis() - lastTelemetryUpdate >= 3000) {
    lastTelemetryUpdate = millis();
    publishTelemetry();
  }

  // 5. Cập nhật màn hình OLED (mỗi 500ms)
  if (millis() - lastDisplayUpdate >= 500) {
    lastDisplayUpdate = millis();
    float dist = readDistanceCM();
    float weight = readWeightGram();
    updateOLED(dist, weight, systemStatus);
  }
}
