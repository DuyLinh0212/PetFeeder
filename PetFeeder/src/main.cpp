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

// ====================================================================================
//                    CẤU HÌNH PHẦN CỨNG & CHÂN (PIN MAPPING)
// ====================================================================================
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

// ====================================================================================
//                    NGƯỠNG & GIỚI HẠN AN TOÀN HỆ THỐNG
// ====================================================================================
const float HOP_CHUA_CAO_CM         = 25.0;  // Chiều cao tối đa bồn chứa
const float NGUONG_HET_HAT_CM       = 20.0;  // Khoảng cách >= 20cm là hết hạt (C05)
const float MAX_BOWL_CAPACITY_G     = 150.0; // Dung tích tối đa của bát ăn để chống tràn (N01)
const float MAX_DAILY_PORTION_G     = 200.0; // Định mức hạt tối đa cho phép trong ngày (N02)
const int   MAX_DAILY_FEEDS         = 6;     // Số lần cho ăn tối đa trong ngày (N02)
const float BOWL_MISSING_THRESHOLD  = -10.0; // Số đo âm sâu biểu thị bát bị lấy ra (N09)
const int   MAX_FEED_PULSES         = 15;    // Giới hạn số nhịp mở servo tối đa (N05)
const float COARSE_FINE_THRESHOLD_G = 10.0;  // Chuyển sang nhịp vi chỉnh khi cách đích <= 10g (N06)
const float OVER_PORTION_TOLERANCE  = 3.0;   // Ngưỡng sai số vượt mức cho phép (N06)

// ====================================================================================
//                    MÔ PHỎNG WOKWI (SIMULATION VARIABLES)
// ====================================================================================
#if defined(PETFEEDER_WOKWI_SIMULATION)
const float SIM_HOPPER_CAPACITY_G = 500.0;
const float SIM_INITIAL_HOPPER_G  = 500.0;
const float SIM_PULSE_GRAMS       = 5.0;
float simulatedHopperGrams        = SIM_INITIAL_HOPPER_G;
float simulatedBowlWeightGrams    = 0.0;
#endif

// ====================================================================================
//                    CẤU HÌNH MẠNG & MQTT
// ====================================================================================
const char* WIFI_SSID     = "Wokwi-GUEST";
const char* WIFI_PASSWORD = "";

#define MQTT_SERVER       "broker.emqx.io"
#define MQTT_PORT         1883
#define MQTT_CLIENT_ID    "ESP32_PetFeeder_Client"
#define MQTT_TOPIC_PREFIX "duylinh0212/petfeeder/v1"

const char* TOPIC_COMMAND   = MQTT_TOPIC_PREFIX "/command";
const char* TOPIC_SCHEDULES = MQTT_TOPIC_PREFIX "/schedules/sync";
const char* TOPIC_CONFIG    = MQTT_TOPIC_PREFIX "/config";
const char* TOPIC_TELEMETRY = MQTT_TOPIC_PREFIX "/telemetry";
const char* TOPIC_EVENTS    = MQTT_TOPIC_PREFIX "/events";
const char* TOPIC_ALERTS    = MQTT_TOPIC_PREFIX "/alerts";

WiFiClient espClient;
PubSubClient mqttClient(espClient);
String mqttClientId = MQTT_CLIENT_ID;

// ====================================================================================
//                    CẤU TRÚC DỮ LIỆU & BIẾN QUẢN LÝ PHIÊN CẤP
// ====================================================================================
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

// Trạng thái khóa & an toàn
volatile bool isDispensing      = false; // Mutex khóa phiên cấp (C03, N03)
bool isSafetyLockout            = false; // Khóa an toàn chất lượng thức ăn (C08)
bool isHopperVerified           = true;  // Cờ xác minh nạp hạt đúng chủng loại (C07)
String foodQualityStatus        = "UNVERIFIED"; // Luôn giữ UNVERIFIED khi chưa có cảm biến chuyên dụng (C08)

// Quản lý hạn mức ngày (N02)
float dailyDispensedGrams       = 0.0;
int   dailyFeedCount            = 0;
int   currentDayTracker         = -1;

// Giám sát biến động bát ngoài phiên cấp (N13, N14)
float lastIdleBowlWeight        = 0.0;
unsigned long lastIdleCheckMs   = 0;

// Hỗ trợ cấp bù sau sự cố (N04)
float lastInterruptedTarget     = 0.0;
float lastInterruptedDelivered  = 0.0;
char  lastProcessedCommandId[40] = "";

// Chống ăn trùng cơ bản (180s)
unsigned long lastFeedSuccessMs = 0;
unsigned long safeIntervalMs    = 180000;
String systemStatus             = "KHOI DONG";

// Nút bấm
unsigned long buttonPressTime   = 0;
bool isButtonPressed           = false;

// Chu kỳ cập nhật
unsigned long lastDisplayUpdate   = 0;
unsigned long lastTelemetryUpdate = 0;
unsigned long lastMQTTReconnect   = 0;

// ====================================================================================
//                    MÃ TRẠNG THÁI CẢM BIẾN (ENUMS)
// ====================================================================================
enum ScaleStatus {
  SCALE_OK,
  SCALE_UNSTABLE,
  SCALE_OFFLINE,
  SCALE_BOWL_MISSING
};

enum UltrasonicStatus {
  ULTRASONIC_OK,
  ULTRASONIC_EMPTY,
  ULTRASONIC_TIMEOUT
};

// ====================================================================================
//                    NGUYÊN MẪU HÀM
// ====================================================================================
void beep(int count, int delayMs);
UltrasonicStatus readDistanceChecked(float &outDistance);
ScaleStatus readStableWeight(float &outWeight, int maxWaitMs = 3000);
float getFastWeight();
float getFastDistance();
void updateOLED(float distance, float weight, String status);
void triggerAntiJam();
bool performFeeding(int targetPortion, bool isOverride, String source, const char* cmdId = nullptr);
void setupWiFi();
void reconnectMQTT();
void mqttCallback(char* topic, byte* message, unsigned int length);
void publishTelemetry();
void publishFeedEvent(const char* cmdId, String status, String source, int targetPortion,
                      float actualWeight, const char* errorCode, String message);
void publishBowlEvent(String eventType, float deltaG, float currentWeightG, String cause);
void checkLocalSchedules();
void checkDayRollover();
void monitorIdleBowl();

// ====================================================================================
//                    ÂM THANH BUZZER
// ====================================================================================
void beep(int count, int delayMs) {
  for (int i = 0; i < count; i++) {
    digitalWrite(PIN_BUZZER, HIGH);
    delay(delayMs);
    digitalWrite(PIN_BUZZER, LOW);
    if (i < count - 1) delay(delayMs);
  }
}

// ====================================================================================
//                    ĐỌC CẢM BIẾN SIÊU ÂM CÓ KIỂM TRA LỖI (N11, C05, C07)
// ====================================================================================
UltrasonicStatus readDistanceChecked(float &outDistance) {
  // Thử đọc tối đa 3 lần để phân biệt Timeout với Hết hạt thật
  for (int attempt = 0; attempt < 3; attempt++) {
    digitalWrite(PIN_TRIG, LOW);
    delayMicroseconds(2);
    digitalWrite(PIN_TRIG, HIGH);
    delayMicroseconds(10);
    digitalWrite(PIN_TRIG, LOW);

    long duration = pulseIn(PIN_ECHO, HIGH, 30000); // 30ms timeout (~5m)
    if (duration > 0) {
      float dist = duration * 0.034 / 2.0;
      outDistance = constrain(dist, 2.0, HOP_CHUA_CAO_CM);

      if (outDistance >= NGUONG_HET_HAT_CM) {
        return ULTRASONIC_EMPTY;
      }
      return ULTRASONIC_OK;
    }
    delay(10);
  }

#if defined(PETFEEDER_WOKWI_SIMULATION)
  // Nếu cảm biến vật lý trên Wokwi không trả duration nhưng đang ở chế độ giả lập
  float level = constrain(simulatedHopperGrams / SIM_HOPPER_CAPACITY_G, 0.0, 1.0);
  outDistance = HOP_CHUA_CAO_CM * (1.0 - level);
  if (outDistance >= NGUONG_HET_HAT_CM) return ULTRASONIC_EMPTY;
  return ULTRASONIC_OK;
#else
  // Cả 3 lần đều duration == 0 -> Lỗi mất tín hiệu cảm biến (N11)
  outDistance = -1.0;
  return ULTRASONIC_TIMEOUT;
#endif
}

float getFastDistance() {
  float d = 0;
  UltrasonicStatus st = readDistanceChecked(d);
  if (st == ULTRASONIC_TIMEOUT) return -1.0;
  return d;
}

// ====================================================================================
//                    ĐỌC CÂN NẶNG HX711 CÓ LỌC ỔN ĐỊNH & KIỂM TRA LỖI (N08, N09, N10)
// ====================================================================================
ScaleStatus readStableWeight(float &outWeight, int maxWaitMs) {
  unsigned long startWait = millis();

  while (millis() - startWait < (unsigned long)maxWaitMs) {
    if (!scale.is_ready()) {
#if !defined(PETFEEDER_WOKWI_SIMULATION)
      delay(50);
      continue;
#endif
    }

    // Lấy 5 mẫu liên tiếp để kiểm tra độ ổn định (N08)
    float samples[5];
    bool readSuccess = true;

    for (int i = 0; i < 5; i++) {
      if (scale.is_ready()) {
        long reading = scale.get_units(1);
        samples[i] = (float)reading / 420.0;
      } else {
#if defined(PETFEEDER_WOKWI_SIMULATION)
        samples[i] = simulatedBowlWeightGrams;
#else
        readSuccess = false;
        break;
#endif
      }
      delay(30);
    }

    if (!readSuccess) {
      delay(50);
      continue;
    }

    // Tìm Min & Max trong 5 mẫu
    float minVal = samples[0];
    float maxVal = samples[0];
    float sumVal = 0;
    for (int i = 0; i < 5; i++) {
      if (samples[i] < minVal) minVal = samples[i];
      if (samples[i] > maxVal) maxVal = samples[i];
      sumVal += samples[i];
    }

    // 1. Kiểm tra mất bát (N09): Trọng lượng âm sâu < -10g
    float avgVal = sumVal / 5.0;
    if (avgVal <= BOWL_MISSING_THRESHOLD) {
      outWeight = avgVal;
      return SCALE_BOWL_MISSING;
    }

    // 2. Kiểm tra độ ổn định (N08): Chênh lệch dao động <= 3.0g
    if ((maxVal - minVal) <= 3.0) {
      if (avgVal < 0.0) avgVal = 0.0;
      outWeight = round(avgVal * 10) / 10.0;
      return SCALE_OK;
    }

    // Nếu dao động > 3.0g: Đang rung lắc hoặc thú tì chân, chờ tiếp
    Serial.printf("[SCALE] Can dao dong: Delta=%.1fg. Dang doi on dinh...\n", (maxVal - minVal));
    delay(100);
  }

  // Hết thời gian chờ mà cân vẫn không sẵn sàng
  if (!scale.is_ready()) {
#if defined(PETFEEDER_WOKWI_SIMULATION)
    outWeight = simulatedBowlWeightGrams;
    return SCALE_OK;
#else
    outWeight = 0;
    return SCALE_OFFLINE; // N10: Cảm biến mất kết nối
#endif
  }

  // Hết thời gian chờ mà cân vẫn chưa ổn định
  outWeight = 0;
  return SCALE_UNSTABLE; // N08: Quá thời hạn chờ ổn định
}

float getFastWeight() {
  if (scale.is_ready()) {
    long reading = scale.get_units(1);
    float w = (float)reading / 420.0;
    return (w < 0.0) ? 0.0 : w;
  }
#if defined(PETFEEDER_WOKWI_SIMULATION)
  return simulatedBowlWeightGrams;
#endif
  return 0.0;
}

// ====================================================================================
//                    MÔ PHỎNG XẢ HẠT (WOKWI PULSE)
// ====================================================================================
#if defined(PETFEEDER_WOKWI_SIMULATION)
void simulateDispensePulse(float pulseAmount, int targetPortion, float initialWeight, float currentWeight) {
  float delivered = currentWeight - initialWeight;
  float remaining = targetPortion - delivered;
  if (remaining <= 0.0 || simulatedHopperGrams <= 0.0) return;

  float dispensed = min(pulseAmount, min(remaining, simulatedHopperGrams));
  simulatedHopperGrams -= dispensed;
  simulatedBowlWeightGrams += dispensed;

  Serial.printf("[SIM] Mo phong: +%.1fg | Kho con: %.1fg | Bat: %.1fg\n",
                dispensed, simulatedHopperGrams, simulatedBowlWeightGrams);
}
#endif

// ====================================================================================
//                    MÀN HÌNH OLED SSD1306
// ====================================================================================
void updateOLED(float distance, float weight, String status) {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextWrap(false);

  // Header
  display.setTextSize(1);
  display.setCursor(6, 0);
  display.print("PETFEEDER - IOT PRO");
  
  if (WiFi.status() == WL_CONNECTED) {
    display.setCursor(118, 0);
    display.print(mqttClient.connected() ? "M" : "W");
  }
  display.drawLine(0, 9, 128, 9, SSD1306_WHITE);

  // Mức hạt bồn chứa
  display.setCursor(0, 13);
  display.print("Hat: ");
  if (distance < 0) {
    display.print("LOI CB!");
  } else if (distance >= NGUONG_HET_HAT_CM) {
    display.print("HET HAT");
  } else {
    int percent = constrain((int)((HOP_CHUA_CAO_CM - distance) / HOP_CHUA_CAO_CM * 100), 0, 100);
    display.print(percent);
    display.print("% (");
    display.print((int)distance);
    display.print("cm)");
  }

  // Khối lượng bát
  display.setCursor(0, 26);
  display.print("Bat: ");
  if (weight <= BOWL_MISSING_THRESHOLD) {
    display.print("MAT BAT!");
  } else {
    display.print(weight, 1);
    display.print("g / 150g");
  }

  // Trạng thái vận hành
  display.setCursor(0, 39);
  display.print("TT: ");
  if (status.length() > 14) status = status.substring(0, 14);
  display.print(status);

  // Trạng thái khóa / an toàn & hướng dẫn
  display.drawLine(0, 52, 128, 52, SSD1306_WHITE);
  display.setCursor(0, 55);
  if (isSafetyLockout) {
    display.print("KHOA AN TOAN!");
  } else if (!isHopperVerified) {
    display.print("CHO XAC MINH NGUON");
  } else {
    display.print("Nhan=AN  Giu=OVR");
  }

  display.display();
}

// ====================================================================================
//                    CƠ CẤU CHỐNG KẸT NÂNG CAO (N12, Section 2.3.3)
// ====================================================================================
void triggerAntiJam() {
  Serial.println("[ANTI-JAM] Phat hien nghi ket hat! Kich hoat co cau tu phuc hoi...");
  systemStatus = "XU LY KET!";
  updateOLED(getFastDistance(), getFastWeight(), systemStatus);
  
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

// ====================================================================================
//                    KIỂM TRA CHUYỂN NGÀY MỚI (N02 - DAILY RESET)
// ====================================================================================
void checkDayRollover() {
  struct tm timeinfo;
  if (getLocalTime(&timeinfo)) {
    int currentDay = timeinfo.tm_yday;
    if (currentDayTracker == -1) {
      currentDayTracker = currentDay;
    } else if (currentDay != currentDayTracker) {
      currentDayTracker = currentDay;
      dailyDispensedGrams = 0.0;
      dailyFeedCount = 0;
      Serial.println("\n>>> [DAILY RESET] Chuyen sang ngay moi 00:00! Reset han muc cho an ngay.");
    }
  }
}

// ====================================================================================
//                    GIÁM SÁT BÁT NGOÀI PHIÊN CẤP (N13: MANUAL REFILL, N14: FOOD DECREASE)
// ====================================================================================
void monitorIdleBowl() {
  if (isDispensing) return;

  unsigned long now = millis();
  if (now - lastIdleCheckMs < 1500) return; // Kiểm tra mỗi 1.5s
  lastIdleCheckMs = now;

  float currentW = 0.0;
  ScaleStatus st = readStableWeight(currentW, 800);
  if (st != SCALE_OK) return;

  if (lastIdleBowlWeight == 0.0) {
    lastIdleBowlWeight = currentW;
    return;
  }

  float delta = currentW - lastIdleBowlWeight;

  // N13: Phát hiện chủ đổ thêm thức ăn trực tiếp vào bát (> 5g)
  if (delta > 5.0) {
    Serial.printf("\n[BOWL MONITOR] Phat hien them thuc an vao bat: %.1fg -> %.1fg (+%.1fg)\n",
                  lastIdleBowlWeight, currentW, delta);
    publishBowlEvent("MANUAL_REFILL", delta, currentW, "OWNER_REFILL");
    lastIdleBowlWeight = currentW;
  }
  // N14: Phát hiện khối lượng bát bị giảm (> 5g) -> Báo cáo UNKNOWN_CAUSE
  else if (delta < -5.0) {
    Serial.printf("\n[BOWL MONITOR] Phat hien can nang giam ngoai phien: %.1fg -> %.1fg (Giam %.1fg)\n",
                  lastIdleBowlWeight, currentW, delta);
    Serial.println("[SAFETY POLICY] Chua co camera xac minh thu cung -> Ghi nhan UNKNOWN_CAUSE!");
    publishBowlEvent("WEIGHT_DECREASED", delta, currentW, "UNKNOWN_CAUSE");
    lastIdleBowlWeight = currentW;
  }
}

// ====================================================================================
//                    BỘ ĐIỀU KHIỂN CẤP THỨC ĂN (FEEDING CONTROLLER - 18 CASES)
// ====================================================================================
bool performFeeding(int targetPortion, bool isOverride, String source, const char* cmdId) {
  unsigned long now = millis();
  char activeCommandId[40];

  if (cmdId && strlen(cmdId) > 0) {
    strncpy(activeCommandId, cmdId, sizeof(activeCommandId) - 1);
  } else {
    snprintf(activeCommandId, sizeof(activeCommandId), "local_%lu", now);
  }

  Serial.printf("\n=======================================================\n");
  Serial.printf(">>> [FEED REQUEST] ID: %s | Nguon: %s | Khau phan: %dg | Override: %s\n",
                activeCommandId, source.c_str(), targetPortion, isOverride ? "YES" : "NO");

  // 1. Chống lặp lệnh & Khóa Mutex phiên cấp (C03, N03)
  if (isDispensing) {
    Serial.println("[REJECTED] Co cau dang ban (BUSY)! Tu choi lenh moi.");
    publishFeedEvent(activeCommandId, "REJECTED", source, targetPortion, 0, "DEVICE_BUSY", "Co cau cap dang hoat dong");
    return false;
  }

  // Chống lặp cùng Command ID đã thực thi gần nhất (C03)
  if (strcmp(activeCommandId, lastProcessedCommandId) == 0 && strlen(activeCommandId) > 0) {
    Serial.println("[BLOCKED] Trung lap command_id da xu ly! Bo qua.");
    publishFeedEvent(activeCommandId, "BLOCKED_DUPLICATE", source, targetPortion, 0, "DUPLICATE_CMD_ID", "Lenh da duoc thuc thi");
    return false;
  }

  // 2. Khóa an toàn chất lượng thực phẩm (C08)
  if (isSafetyLockout && !isOverride) {
    Serial.println("[SAFETY LOCKOUT] He thong dang bi khoa an toan do nghi ngo thuc an hong!");
    systemStatus = "KHOA AN TOAN!";
    updateOLED(getFastDistance(), getFastWeight(), systemStatus);
    beep(3, 100);
    publishFeedEvent(activeCommandId, "REJECTED", source, targetPortion, 0, "SAFETY_LOCKOUT", "He thong dang bi khoa an toan");
    return false;
  }

  // 3. Kiểm tra xác minh nạp hạt mới (C07)
  if (!isHopperVerified && !isOverride) {
    Serial.println("[UNVERIFIED REFILL] Phat hien nap hat chua xac minh chung loai!");
    systemStatus = "CHO XAC MINH";
    updateOLED(getFastDistance(), getFastWeight(), systemStatus);
    beep(2, 150);
    publishFeedEvent(activeCommandId, "REJECTED", source, targetPortion, 0, "UNVERIFIED_FOOD", "Vui long xac nhan hat an toan tren App");
    return false;
  }

  // 4. Kiểm tra giới hạn ngày (N02)
  checkDayRollover();
  if (!isOverride) {
    if (dailyFeedCount >= MAX_DAILY_FEEDS || (dailyDispensedGrams + targetPortion > MAX_DAILY_PORTION_G)) {
      Serial.printf("[DAILY LIMIT] Da vuot nguong ngay: %d/%d lan | %.1f/%.1fg\n",
                    dailyFeedCount, MAX_DAILY_FEEDS, dailyDispensedGrams, MAX_DAILY_PORTION_G);
      systemStatus = "VUOT HAN MUC";
      updateOLED(getFastDistance(), getFastWeight(), systemStatus);
      beep(3, 80);
      publishFeedEvent(activeCommandId, "REJECTED", source, targetPortion, 0, "DAILY_LIMIT_EXCEEDED", "Vuot qua gioi han an trong ngay");
      delay(1200);
      systemStatus = "SAN SANG";
      return false;
    }
  }

  // 5. Kiểm tra khoảng cách an toàn chống ăn trùng (180s - C03, N02)
  if (!isOverride && lastFeedSuccessMs > 0 && (now - lastFeedSuccessMs < safeIntervalMs)) {
    unsigned long elapsedSec = (now - lastFeedSuccessMs) / 1000;
    Serial.printf("[BLOCKED] Vua cho an cach day %lus (nguong %lus). Bi chan!\n",
                  elapsedSec, safeIntervalMs / 1000);
    systemStatus = "BLOCKED: VUA AN";
    updateOLED(getFastDistance(), getFastWeight(), systemStatus);

    for (int i = 0; i < 2; i++) {
      digitalWrite(PIN_LED_RED, HIGH);
      digitalWrite(PIN_BUZZER, HIGH);
      delay(100);
      digitalWrite(PIN_LED_RED, LOW);
      digitalWrite(PIN_BUZZER, LOW);
      delay(100);
    }

    publishFeedEvent(activeCommandId, "BLOCKED_DUPLICATE", source, targetPortion, 0, "SAFE_INTERVAL_ACTIVE", "Vua moi cho an");
    delay(1200);
    systemStatus = "SAN SANG";
    return false;
  }

  // 6. Kiểm tra phần cứng Cân HX711 & Độ ổn định (N08, N09, N10)
  float initialBowlWeight = 0.0;
  ScaleStatus scaleSt = readStableWeight(initialBowlWeight, 3000);

  if (scaleSt == SCALE_OFFLINE) {
    Serial.println("[LOI PHAN CUNG] Cảm biến HX711 không sẵn sàng!");
    systemStatus = "LOI: HONG CAN!";
    updateOLED(getFastDistance(), 0, systemStatus);
    beep(4, 150);
    publishFeedEvent(activeCommandId, "SENSOR_ERROR", source, targetPortion, 0, "HX711_OFFLINE", "Cam bien can bi dut day");
    return false;
  }
  if (scaleSt == SCALE_BOWL_MISSING) {
    Serial.println("[BOWL MISSING] Không phát hiện bát thức ăn trên đế cân!");
    systemStatus = "MAT BAT THUC AN!";
    updateOLED(getFastDistance(), initialBowlWeight, systemStatus);
    beep(4, 100);
    publishFeedEvent(activeCommandId, "REJECTED", source, targetPortion, 0, "BOWL_MISSING", "Bat thuc an bi lay khoi de can");
    return false;
  }
  if (scaleSt == SCALE_UNSTABLE) {
    Serial.println("[UNSTABLE] Cân dao động quá mức! Nghi ngờ thú đang tì chân.");
    systemStatus = "CAN KHONG ON DINH";
    updateOLED(getFastDistance(), initialBowlWeight, systemStatus);
    beep(2, 200);
    publishFeedEvent(activeCommandId, "REJECTED", source, targetPortion, 0, "SCALE_UNSTABLE", "Can dao dong do thu ty chan");
    return false;
  }

  // 7. Kiểm tra cảm biến siêu âm & Mức hạt bồn chứa (C05, N11)
  float hopperDist = 0.0;
  UltrasonicStatus usSt = readDistanceChecked(hopperDist);

  if (usSt == ULTRASONIC_TIMEOUT) {
    Serial.println("[SENSOR ERROR] Cảm biến siêu âm HC-SR04 mất tín hiệu (timeout)!");
    systemStatus = "LOI: CB SIEU AM";
    updateOLED(-1.0, initialBowlWeight, systemStatus);
    beep(3, 150);
    publishFeedEvent(activeCommandId, "SENSOR_ERROR", source, targetPortion, 0, "ULTRASONIC_TIMEOUT", "Cam bien sieu am khong phan hoi");
    return false;
  }
  if (usSt == ULTRASONIC_EMPTY && !isOverride) {
    Serial.println("[EMPTY] Hộp chứa đã hết hạt!");
    systemStatus = "LOI: HET HAT";
    updateOLED(hopperDist, initialBowlWeight, systemStatus);
    digitalWrite(PIN_LED_RED, HIGH);
    beep(4, 150);
    digitalWrite(PIN_LED_RED, LOW);
    publishFeedEvent(activeCommandId, "FOOD_EMPTY", source, targetPortion, 0, "HOPPER_EMPTY", "Hop chua het hat");
    delay(1200);
    systemStatus = "SAN SANG";
    return false;
  }

  // 8. Chống tràn bát & Xử lý khẩu phần bù (N01)
  float effectivePortion = (float)targetPortion;
  if (initialBowlWeight + effectivePortion > MAX_BOWL_CAPACITY_G) {
    float roomLeft = MAX_BOWL_CAPACITY_G - initialBowlWeight;
    if (roomLeft <= 2.0) {
      Serial.printf("[BOWL FULL] Bát đã đầy (%.1fg >= 150g). Từ chối cấp để chống tràn!\n", initialBowlWeight);
      systemStatus = "BAT DA DAY!";
      updateOLED(hopperDist, initialBowlWeight, systemStatus);
      beep(2, 150);
      publishFeedEvent(activeCommandId, "REJECTED", source, targetPortion, 0, "BOWL_FULL", "Bat da day, khong the cap them");
      delay(1200);
      systemStatus = "SAN SANG";
      return false;
    }
    Serial.printf("[TOP-UP] Bát còn %.1fg. Điều chỉnh khẩu phần bù: %.1fg -> %.1fg để không tràn!\n",
                  initialBowlWeight, effectivePortion, roomLeft);
    effectivePortion = roomLeft;
  }

  // Kiểm tra nếu đây là lệnh Retry cấp bù sau lỗi kẹt (N04)
  if (source == "retry" && lastInterruptedTarget > 0) {
    float remainingNeeded = lastInterruptedTarget - lastInterruptedDelivered;
    if (remainingNeeded > 0) {
      effectivePortion = min(effectivePortion, remainingNeeded);
      Serial.printf("[RETRY] Tự động tính lượng bù còn thiếu từ phiên trước: %.1fg\n", effectivePortion);
    }
  }

  // ==================== BẮT ĐẦU PHIÊN CẤP VÒNG KÍN ====================
  isDispensing = true;
  strncpy(lastProcessedCommandId, activeCommandId, sizeof(lastProcessedCommandId) - 1);
  digitalWrite(PIN_LED_GREEN, HIGH);
  systemStatus = isOverride ? "OVERRIDE FEED" : "DANG CHO AN...";
  updateOLED(hopperDist, initialBowlWeight, systemStatus);
  beep(1, 150);

  int pulses = 0;
  int jamSuspectCount = 0;
  const int MAX_JAM_RETRIES = 3;
  float currentWeight = initialBowlWeight;
  bool isOverPortion = false;
  bool isPetInterfered = false;

  while ((currentWeight - initialBowlWeight) < effectivePortion && pulses < MAX_FEED_PULSES) {
    pulses++;
    float weightBeforePulse = currentWeight;
    float remaining = effectivePortion - (currentWeight - initialBowlWeight);

    // Thuật toán cấp 2 pha: Coarse vs Fine Pulse (N06)
    if (remaining > COARSE_FINE_THRESHOLD_G) {
      // Nhịp thô: góc mở 90 độ, giữ 500ms
      servoFeed.write(90);
      delay(500);
      servoFeed.write(0);
      delay(400);
#if defined(PETFEEDER_WOKWI_SIMULATION)
      simulateDispensePulse(SIM_PULSE_GRAMS, effectivePortion, initialBowlWeight, currentWeight);
#endif
    } else {
      // Nhịp vi chỉnh (Fine Pulse): góc mở 60 độ, nhấp 200ms, trễ 600ms chờ hạt rơi hết
      Serial.println("[FINE PULSE] Cach dich <= 10g: Nhap vi chinh 200ms...");
      servoFeed.write(60);
      delay(200);
      servoFeed.write(0);
      delay(600);
#if defined(PETFEEDER_WOKWI_SIMULATION)
      simulateDispensePulse(min(2.5f, remaining), effectivePortion, initialBowlWeight, currentWeight);
#endif
    }

    currentWeight = getFastWeight();
    float pulseGain = currentWeight - weightBeforePulse;
    Serial.printf("[PULSE %d] Bat: %.1fg (+%.1fg) | Muc tieu: %.1fg\n",
                  pulses, currentWeight, pulseGain, effectivePortion);

    // N07: Phát hiện thú ăn / thò đầu vào bát giữa phiên cấp (cân giảm đột ngột > 2g)
    if (pulseGain < -2.0) {
      Serial.printf("[CANH BAO AN TOAN] Can giam dot ngot: %.1fg! Nghi thu dang an.\n", pulseGain);
      isPetInterfered = true;
      break;
    }

    // N06: Kiểm tra cấp quá lượng
    if ((currentWeight - initialBowlWeight) > (effectivePortion + OVER_PORTION_TOLERANCE)) {
      Serial.println("[OVER_PORTION] Vuot nguong toi da! Dung servo ngay.");
      isOverPortion = true;
      break;
    }

    // N12: Kiểm tra kẹt hạt khi nhịp tăng không đáng kể
    if (pulseGain < 1.0) {
      jamSuspectCount++;
      Serial.printf("[CANH BAO] Khong tang can (<1g). Lan nghi ket: %d/%d\n", jamSuspectCount, MAX_JAM_RETRIES);
      triggerAntiJam();

      if (jamSuspectCount >= MAX_JAM_RETRIES) {
        Serial.println("[JAM ERROR] Da thu go ket 3 lan khong thanh cong!");
        break;
      }
    } else {
      jamSuspectCount = 0; // Đã ra hạt bình thường
    }

    publishTelemetry();
    updateOLED(getFastDistance(), currentWeight, systemStatus);
  }

  // Kết thúc phiên cấp
  servoFeed.write(0);
  servoAnti.write(90);
  digitalWrite(PIN_LED_GREEN, LOW);

  float actualDispensed = currentWeight - initialBowlWeight;
  if (actualDispensed < 0) actualDispensed = 0.0;
  lastIdleBowlWeight = currentWeight;

  // Xử lý các tình huống kết thúc
  if (isPetInterfered) {
    // N07: Thú tiếp cận / cướp ăn
    systemStatus = "DUNG: THU AN!";
    updateOLED(getFastDistance(), currentWeight, systemStatus);
    beep(2, 100);
    publishFeedEvent(activeCommandId, "INTERRUPTED", source, targetPortion, actualDispensed,
                     "INTERRUPTED_PET_FEEDING", "Tam dung do phat hien thu cung tiep can bat");
  } else if (jamSuspectCount >= MAX_JAM_RETRIES) {
    // N04 & N12: Kẹt hạt
    systemStatus = "LOI KET HAT";
    updateOLED(getFastDistance(), currentWeight, systemStatus);
    digitalWrite(PIN_LED_RED, HIGH);
    beep(5, 200);
    digitalWrite(PIN_LED_RED, LOW);

    lastInterruptedTarget = effectivePortion;
    lastInterruptedDelivered = actualDispensed;
    publishFeedEvent(activeCommandId, "JAM_ERROR", source, targetPortion, actualDispensed,
                     "JAM_RECOVERY_FAILED", "Co cau bi ket hat, khong the cap them");
  } else if (pulses >= MAX_FEED_PULSES && (effectivePortion - actualDispensed > 2.0)) {
    // N05: Hết nhịp cấp tối đa mà chưa đủ hạt
    systemStatus = "CAP THIEU!";
    updateOLED(getFastDistance(), currentWeight, systemStatus);
    beep(3, 100);
    publishFeedEvent(activeCommandId, "PARTIAL", source, targetPortion, actualDispensed,
                     "MAX_PULSES_REACHED", "Da dat gioi han nhip cap ma chua du khau phan");
  } else {
    // Hoàn tất thành công (N06 có thể kèm cờ OVER_PORTION)
    systemStatus = "HOAN TAT!";
    updateOLED(getFastDistance(), currentWeight, systemStatus);
    beep(2, 100);
    lastFeedSuccessMs = millis();
    dailyDispensedGrams += actualDispensed;
    dailyFeedCount++;

    const char* errCode = isOverPortion ? "OVER_PORTION" : "NONE";
    String msg = isOverPortion ? "Cap thanh cong (co du nhe do quan tinh)" : "Cho an thanh cong!";
    publishFeedEvent(activeCommandId, "SUCCESS", source, targetPortion, actualDispensed, errCode, msg);

    lastInterruptedTarget = 0;
    lastInterruptedDelivered = 0;
  }

  publishTelemetry();
  delay(1500);
  isDispensing = false;
  systemStatus = "SAN SANG";
  updateOLED(getFastDistance(), currentWeight, systemStatus);
  return (systemStatus == "HOAN TAT!");
}

// ====================================================================================
//                    GỬI SỰ KIỆN FEED_RESULT (CHUẨN HỢP ĐỒNG DANH & LONG)
// ====================================================================================
void publishFeedEvent(const char* cmdId, String status, String source, int targetPortion,
                      float actualWeight, const char* errorCode, String message) {
  if (!mqttClient.connected()) {
    Serial.println("[MQTT] Ngoai tuyen: Khong the gui feed event truc tiep");
    return;
  }

  JsonDocument doc;
  doc["command_id"]       = cmdId ? cmdId : "unknown";
  doc["event"]            = "FEED_RESULT";
  doc["status"]           = status;
  doc["source"]           = source;
  doc["target_portion_g"] = targetPortion;
  doc["actual_weight_g"]  = round(actualWeight * 10) / 10.0;
  doc["error_code"]       = errorCode;
  doc["message"]          = message;
  doc["timestamp"]        = (unsigned long)time(nullptr);

  char buffer[320];
  serializeJson(doc, buffer);
  mqttClient.publish(TOPIC_EVENTS, buffer, true);
  Serial.printf("[MQTT OUT] Event: %s\n", buffer);
}

// ====================================================================================
//                    GỬI SỰ KIỆN BIẾN ĐỘNG BÁT BOWL_EVENT (N13, N14)
// ====================================================================================
void publishBowlEvent(String eventType, float deltaG, float currentWeightG, String cause) {
  if (!mqttClient.connected()) return;

  JsonDocument doc;
  doc["event"]                 = "BOWL_EVENT";
  doc["type"]                  = eventType;
  doc["delta_g"]               = round(deltaG * 10) / 10.0;
  doc["current_bowl_weight_g"] = round(currentWeightG * 10) / 10.0;
  doc["cause"]                 = cause;
  doc["timestamp"]             = (unsigned long)time(nullptr);

  char buffer[256];
  serializeJson(doc, buffer);
  mqttClient.publish(TOPIC_EVENTS, buffer, true);
  Serial.printf("[MQTT OUT] Bowl Event: %s\n", buffer);
}

// ====================================================================================
//                    GỬI TELEMETRY ĐỊNH KỲ
// ====================================================================================
void publishTelemetry() {
  if (!mqttClient.connected()) return;

  float dist = getFastDistance();
  float weight = getFastWeight();
  int percent = (dist < 0) ? 0 : constrain((int)((HOP_CHUA_CAO_CM - dist) / HOP_CHUA_CAO_CM * 100), 0, 100);

  JsonDocument doc;
  doc["device_id"]            = "petfeeder_01";
  doc["distance_cm"]          = round(dist * 10) / 10.0;
  doc["food_level_percent"]   = percent;
  doc["bowl_weight_g"]        = round(weight * 10) / 10.0;
  doc["status"]               = systemStatus;
  doc["food_quality_status"]  = foodQualityStatus;
  doc["hopper_verified"]      = isHopperVerified;
  doc["is_safety_lockout"]    = isSafetyLockout;
  doc["daily_dispensed_g"]    = round(dailyDispensedGrams * 10) / 10.0;
  doc["daily_feed_count"]     = dailyFeedCount;
  doc["uptime"]               = millis() / 1000;

  char buffer[384];
  serializeJson(doc, buffer);
  mqttClient.publish(TOPIC_TELEMETRY, buffer, true);
}

// ====================================================================================
//                    XỬ LÝ MQTT MESSAGE TỪ BACKEND
// ====================================================================================
void mqttCallback(char* topic, byte* message, unsigned int length) {
  String payload = "";
  for (unsigned int i = 0; i < length; i++) {
    payload += (char)message[i];
  }
  Serial.printf("\n[MQTT IN] Topic: %s | Payload: %s\n", topic, payload.c_str());

  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, payload);
  if (err) {
    Serial.printf("[MQTT Error] JSON loi: %s\n", err.c_str());
    return;
  }

  // 1. Nhận lệnh cho ăn ngay (FR-08 & C03)
  if (String(topic) == TOPIC_COMMAND) {
    String cmd = doc["command"] | "";
    if (cmd == "FEED" || cmd == "RETRY") {
      int portion = doc["portion"] | (doc["target_portion_g"] | 30);
      bool override = doc["override"] | false;
      String src = doc["source"] | "app";
      const char* cmdId = doc["command_id"] | "";
      unsigned long expiresAt = doc["expires_at"] | 0;

      // Kiểm tra hết hạn lệnh (N25)
      if (expiresAt > 0 && (unsigned long)time(nullptr) > expiresAt) {
        Serial.println("[EXPIRED] Lenh MQTT da qua thoi gian het han! Tu choi.");
        publishFeedEvent(cmdId, "REJECTED", src, portion, 0, "COMMAND_EXPIRED", "Lenh da qua thoi diem het han");
        return;
      }

      performFeeding(portion, override, (cmd == "RETRY") ? "retry" : src, cmdId);
    }
  }

  // 2. Nhận cấu hình hệ thống & Khóa an toàn (C07, C08, N02)
  else if (String(topic) == TOPIC_CONFIG) {
    if (doc["config"]) {
      JsonObject cfg = doc["config"];
      if (cfg["safe_interval_sec"]) {
        safeIntervalMs = (unsigned long)cfg["safe_interval_sec"] * 1000;
        Serial.printf("[CONFIG] Safe interval = %lums\n", safeIntervalMs);
      }
      if (cfg["lockdown"].is<bool>()) {
        isSafetyLockout = cfg["lockdown"].as<bool>();
        Serial.printf("[CONFIG] Safety Lockout = %s\n", isSafetyLockout ? "ACTIVATED" : "DEACTIVATED");
        if (isSafetyLockout) {
          systemStatus = "KHOA AN TOAN!";
          digitalWrite(PIN_LED_RED, HIGH);
        } else {
          systemStatus = "SAN SANG";
          digitalWrite(PIN_LED_RED, LOW);
        }
      }
      if (cfg["verify_refill"].is<bool>() && cfg["verify_refill"].as<bool>()) {
        isHopperVerified = true;
        Serial.println("[CONFIG] Da xac nhan nguon hat an toan!");
        systemStatus = "SAN SANG";
      }
    }
  }

  // 3. Nhận đồng bộ lịch (FR-04)
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
}

// ====================================================================================
//                    KIỂM TRA LỊCH CỤC BỘ (OFFLINE SCHEDULES - N03)
// ====================================================================================
void checkLocalSchedules() {
  if (isDispensing) return; // N03: Không ngắt phiên đang chạy

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
          Serial.printf("\n[AUTO SCHEDULE] Kich hoat lich %02d:%02d (%dg)\n",
                        currentHour, currentMin, localSchedules[i].portion);
          char schedCmdId[32];
          snprintf(schedCmdId, sizeof(schedCmdId), "sched_%s_%d", localSchedules[i].id, currentDay);
          performFeeding(localSchedules[i].portion, false, "schedule", schedCmdId);
        }
      }
    }
  }
}

// ====================================================================================
//                    KẾT NỐI WIFI & NTP
// ====================================================================================
void setupWiFi() {
  Serial.printf("\n[WiFi] Dang ket noi toi SSID: %s\n", WIFI_SSID);
  systemStatus = "KET NOI WIFI...";
  updateOLED(getFastDistance(), getFastWeight(), systemStatus);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(400);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[WiFi] Da ket noi thanh cong!");
    Serial.printf("[WiFi] IP: %s\n", WiFi.localIP().toString().c_str());
    configTime(7 * 3600, 0, "pool.ntp.org", "time.google.com");
  } else {
    Serial.println("\n[WiFi] Khong the ket noi Wi-Fi! Chay che do ngoai tuyen.");
  }
}

// ====================================================================================
//                    KẾT NỐI MQTT BROKER
// ====================================================================================
void reconnectMQTT() {
  if (mqttClient.connected() || WiFi.status() != WL_CONNECTED) return;

  unsigned long now = millis();
  if (now - lastMQTTReconnect < 4000) return;
  lastMQTTReconnect = now;

  Serial.printf("[MQTT] Dang ket noi toi Broker: %s:%d...\n", MQTT_SERVER, MQTT_PORT);
  if (mqttClient.connect(mqttClientId.c_str())) {
    Serial.println("[MQTT] Da ket noi thanh cong!");
    mqttClient.subscribe(TOPIC_COMMAND);
    mqttClient.subscribe(TOPIC_SCHEDULES);
    mqttClient.subscribe(TOPIC_CONFIG);
    beep(1, 80);
  } else {
    Serial.printf("[MQTT] Ket noi that bai, ma loi rc=%d\n", mqttClient.state());
  }
}

// ====================================================================================
//                    KHỞI TẠO HỆ THỐNG (SETUP)
// ====================================================================================
void setup() {
  Serial.begin(115200);
  Serial.println("\n=============================================");
  Serial.println("  PETFEEDER IOT - HE THONG CAP HAT AN TOAN   ");
  Serial.println("  Author: Ngo Cong Danh - Nhom 7             ");
  Serial.println("=============================================");

  uint64_t chipId = ESP.getEfuseMac();
  mqttClientId = String(MQTT_CLIENT_ID) + "_" +
                 String((uint32_t)(chipId >> 32), HEX) +
                 String((uint32_t)chipId, HEX);

  pinMode(PIN_TRIG, OUTPUT);
  pinMode(PIN_ECHO, INPUT);
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  pinMode(PIN_LED_GREEN, OUTPUT);
  pinMode(PIN_LED_RED, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);

  digitalWrite(PIN_LED_GREEN, LOW);
  digitalWrite(PIN_LED_RED, LOW);
  digitalWrite(PIN_BUZZER, LOW);

  servoFeed.attach(PIN_SERVO_FEED);
  servoAnti.attach(PIN_SERVO_ANTI);
  servoFeed.write(0);
  servoAnti.write(90);

  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("[LOI] Khong the tim thay OLED SSD1306!");
  }
  display.clearDisplay();

  scale.begin(PIN_HX711_DT, PIN_HX711_SCK);
  scale.set_scale();
  scale.tare();

  beep(1, 150);
  systemStatus = "KHOI DONG";
  updateOLED(getFastDistance(), getFastWeight(), systemStatus);

  setupWiFi();
  mqttClient.setServer(MQTT_SERVER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);

  systemStatus = "SAN SANG";
  updateOLED(getFastDistance(), getFastWeight(), systemStatus);
  lastIdleBowlWeight = getFastWeight();
}

// ====================================================================================
//                    VÒNG LẶP CHÍNH (LOOP)
// ====================================================================================
void loop() {
  // 1. Quản lý MQTT
  if (WiFi.status() == WL_CONNECTED) {
    if (!mqttClient.connected()) {
      reconnectMQTT();
    } else {
      mqttClient.loop();
    }
  }

  // 2. Xử lý nút bấm vật lý (Debounce 50ms & Long-press Override > 2.5s)
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

      // Nạp mở khóa xác minh nguồn thức ăn nếu đang chờ xác minh (C07)
      if (!isHopperVerified && duration >= 2500) {
        isHopperVerified = true;
        Serial.println("[BUTTON] Da xac nhan hat an toan qua nut bam vat ly!");
        beep(2, 100);
        systemStatus = "SAN SANG";
      }
      // Nhấn giữ > 2.5s: Override feed (C05, Section 2.3.1)
      else if (duration >= 2500) {
        Serial.println("[BUTTON] Nhan giu >2.5s: Kich hoat OVERRIDE FEED!");
        beep(1, 400);
        performFeeding(30, true, "override");
      }
      // Nhấn nhả thông thường 50ms - 2.5s (C03)
      else if (duration >= 50) {
        Serial.println("[BUTTON] Nhan nha: Kich hoat cho an tai cho!");
        performFeeding(30, false, "button");
      }
    }
  }

  // 3. Giám sát biến động bát ngoài phiên cấp (N13, N14)
  monitorIdleBowl();

  // 4. Kiểm tra lịch tự động (FR-03, FR-04, N03)
  static unsigned long lastScheduleCheck = 0;
  if (millis() - lastScheduleCheck >= 1000) {
    lastScheduleCheck = millis();
    checkLocalSchedules();
  }

  // 5. Gửi Telemetry định kỳ mỗi 3s
  if (millis() - lastTelemetryUpdate >= 3000) {
    lastTelemetryUpdate = millis();
    publishTelemetry();
  }

  // 6. Cập nhật OLED mỗi 500ms
  if (millis() - lastDisplayUpdate >= 500) {
    lastDisplayUpdate = millis();
    updateOLED(getFastDistance(), getFastWeight(), systemStatus);
  }
}
