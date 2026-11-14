// Main circuit by Danh, extended with Long's persistent command/schedule controller.
// ESP32, portion servo, HX711, OLED, button, LEDs and buzzer.
#include <Arduino.h>
#include <WiFi.h>
#include <MQTT.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <Preferences.h>
#include <esp_partition.h>
#if WOKWI_SIM
#include <esp_littlefs.h>
#endif
#include <HX711.h>
#include <time.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#if __has_include("secrets.h")
#include "secrets.h"
#else
#include "secrets.example.h"
#endif

constexpr int SERVO_PIN=13, BUTTON_PIN=4, DT_PIN=19, SCK_PIN=23;
constexpr int TRIG_PIN=5, ECHO_PIN=18;
constexpr float TANK_HEIGHT_CM=25.0f, HOPPER_CAPACITY_G=500.0f;
constexpr int GREEN_PIN=2, RED_PIN=15, BUZZER_PIN=14;
Adafruit_SSD1306 display(128,64,&Wire,-1);
bool oledOK=false,simAuto=false;
#if WOKWI_SIM
bool simMqttOffline=false;
#endif
float pulseBaseline=0;
unsigned long displayAt=0,buzzUntil=0;
bool finePulse=false,bowlMissing=false,weightDropped=false;
String uiStatus="KHOI DONG";
void toneNotice(unsigned long duration=100){digitalWrite(BUZZER_PIN,HIGH);buzzUntil=millis()+duration;}
void servoAngle(int angle){ledcWrite(0,(uint32_t)((500+angle*2000/180)*65535UL/20000));}
constexpr size_t MAX_EVENTS=96, MAX_HISTORY=32;
constexpr unsigned long AUTO_RECONCILE_STABLE_MS=2000;
WiFiClient wifiClient;
MQTTClient mqtt(4096);
HX711 scale;
Preferences nvs;
JsonDocument state;
bool storageOK=false,nvsReady=false,legacyFsReady=false,weightOK=false,busy=false,motorOpen=false;
constexpr size_t WEIGHT_FILTER_SAMPLES=5,WEIGHT_STABILITY_SAMPLES=3;
float weightG=0,lastSample=0,weightSum=0;
float weightSamples[WEIGHT_FILTER_SAMPLES]={0};
size_t weightSampleCount=0,weightSampleIndex=0;
float weightWindow[WEIGHT_STABILITY_SAMPLES]={0};
size_t weightWindowCount=0,weightWindowIndex=0;
unsigned long lastWeightAt=0;
bool weightStartupReported=false,weightDeviationReported=false;
unsigned long sampleAt=0,stableAt=0,beatAt=0,publishAt=0,connectAt=0,scanAt=0,hopperAt=0;
unsigned long feedAt=0,servoAt=0;
unsigned long scanSavedAt=0;
String serialLine;
String bootId;
String root=MQTT_TOPIC_PREFIX;
String mqttClientId;
bool clockSyncReported=false,syncTelemetryPending=false,recoveryPending=false;
unsigned long recoveryPendingSince=0;
float distanceCM=NAN;
bool validTime(){return time(nullptr)>1700000000;}
long nowSec(){return (long)time(nullptr);}
void servo(bool open){motorOpen=open;servoAngle(open?(finePulse?60:state["config"]["pulse_step_angle"].as<int>()):0);}
void updatePanel(){
  digitalWrite(GREEN_PIN,busy);
  digitalWrite(RED_PIN,!storageOK||state["locked"].as<bool>()||state["overflow_count"].as<unsigned long>()>0||uiStatus=="SENSOR_ERROR"||uiStatus=="BOWL_MISSING");
  if(buzzUntil&&(long)(millis()-buzzUntil)>=0){digitalWrite(BUZZER_PIN,LOW);buzzUntil=0;}
  if(!oledOK||millis()-displayAt<500)return;displayAt=millis();
  display.clearDisplay();display.setTextColor(SSD1306_WHITE);display.setTextSize(1);display.setCursor(0,0);
  display.println("PETFEEDER NHOM 7");
  display.print("Hop: ");if(isfinite(distanceCM))display.print((int)constrain((1-distanceCM/TANK_HEIGHT_CM)*100,0.0f,100.0f));else display.print("?");display.println("%");
  display.print("Bat: ");if(weightOK)display.print(weightG,1);else display.print("?");display.println(" g");
  display.print("Ngay: ");display.print(state["used_g"].as<float>(),0);display.print("/");display.print(state["config"]["daily_limit_g"].as<float>(),0);display.print("g ");display.print(state["feed_count"].as<int>());display.println(" bua");
  display.print("TT: ");display.println(!storageOK?"STORAGE LOCK":busy?"DANG CAP":uiStatus);
  display.print("MQTT: ");display.println(mqtt.connected()?"ON":"OFF");
  display.print(simAuto?"DEMO AUTO":"HX711 MANUAL");display.display();
}
bool persist(){
  if(!storageOK||!nvsReady)return false;
  String serialized;serializeJson(state,serialized);
  if(!serialized.length()||nvs.putString("state",serialized.c_str())==0){
    servo(false);storageOK=false;Serial.println("LỖI NVS: Không lưu được trạng thái; đã khóa cơ cấu cấp để bảo vệ.");return false;
  }
  String readback=nvs.getString("state","");JsonDocument check;
  if(readback!=serialized||deserializeJson(check,readback)){
    servo(false);storageOK=false;Serial.println("LỖI NVS: Đọc kiểm tra dữ liệu không khớp; đã khóa cơ cấu cấp.");return false;
  }
  return true;
}
bool stateFileExists(){
  return legacyFsReady&&LittleFS.exists("/state.json");
}
#if WOKWI_SIM
bool blankSimulationStorage(){
  const esp_partition_t* partition=esp_partition_find_first(ESP_PARTITION_TYPE_DATA,ESP_PARTITION_SUBTYPE_DATA_SPIFFS,"spiffs");
  if(!partition||partition->encrypted)return false;
  uint8_t block[512];
  for(size_t offset=0;offset<partition->size;offset+=sizeof(block)){
    const size_t count=min(sizeof(block),partition->size-offset);
    if(esp_partition_read(partition,offset,block,count)!=ESP_OK)return false;
    for(size_t i=0;i<count;i++)if(block[i]!=0xff)return false;
    yield();
  }
  return true;
}
#endif
JsonObject cfg(){return state["config"].as<JsonObject>();}
float cf(const char* key){return cfg()[key].as<float>();}
void resetWeightFilter(unsigned long ms){
  weightSum=0;weightSampleCount=0;weightSampleIndex=0;
  weightWindowCount=0;weightWindowIndex=0;
  weightG=0;lastSample=0;weightDropped=false;stableAt=ms;
}
bool weightFilterReady(){return weightSampleCount>=WEIGHT_FILTER_SAMPLES;}
void trackWeight(float sample,unsigned long ms){
  if(!isfinite(sample)){resetWeightFilter(ms);return;}
  if(weightSampleCount<WEIGHT_FILTER_SAMPLES){
    weightSamples[weightSampleIndex]=sample;weightSum+=sample;weightSampleCount++;
  }else{
    weightSum+=sample-weightSamples[weightSampleIndex];weightSamples[weightSampleIndex]=sample;
  }
  weightSampleIndex=(weightSampleIndex+1)%WEIGHT_FILTER_SAMPLES;
  const float filtered=weightSum/weightSampleCount;
  weightG=filtered;
  const bool ready=weightFilterReady();
  weightDropped=busy&&ready&&filtered-lastSample < -2;
  lastSample=filtered;
  float windowSpan=0;
  if(!ready){weightWindowCount=0;weightWindowIndex=0;stableAt=ms;}
  else{
    weightWindow[weightWindowIndex]=filtered;
    weightWindowIndex=(weightWindowIndex+1)%WEIGHT_STABILITY_SAMPLES;
    if(weightWindowCount<WEIGHT_STABILITY_SAMPLES)weightWindowCount++;
    float lo=filtered,hi=filtered;
    for(size_t i=0;i<weightWindowCount;i++){lo=min(lo,weightWindow[i]);hi=max(hi,weightWindow[i]);}
    windowSpan=hi-lo;
    if(weightWindowCount<WEIGHT_STABILITY_SAMPLES||windowSpan>cf("tolerance_g"))stableAt=ms;
  }
#if WOKWI_SIM
  if(!simAuto&&ready&&weightWindowCount>=WEIGHT_STABILITY_SAMPLES){
    const float tolerance=cf("tolerance_g");
    if(!weightStartupReported&&windowSpan<=tolerance&&ms-stableAt>=700){
      Serial.printf("[HX711] Cân ổn định lúc khởi động: mẫu %.1f g | MA5 %.1f g\n",sample,filtered);
      weightStartupReported=true;
    }else if(weightStartupReported&&windowSpan>tolerance&&!weightDeviationReported){
      Serial.printf("[HX711] CẢNH BÁO CÂN DAO ĐỘNG: biên độ MA5 %.1f g, ngưỡng %.1f g | mẫu %.1f g | MA5 %.1f g\n",windowSpan,tolerance,sample,filtered);
      weightDeviationReported=true;
    }else if(weightDeviationReported&&windowSpan<=tolerance&&ms-stableAt>=700){
      Serial.printf("[HX711] Cân ổn định trở lại | MA5 %.1f g\n",filtered);
      weightDeviationReported=false;
    }
  }
#endif
  lastWeightAt=ms;
}
String id(){char b[17];snprintf(b,sizeof(b),"%08lx%08lx",(unsigned long)esp_random(),(unsigned long)esp_random());return String(b);}
void defaults(){
  JsonObject c=state["config"].to<JsonObject>();
  c["max_portion_g"]=100;c["daily_limit_g"]=200;c["min_interval_s"]=180;
  c["command_ttl_s"]=60;
  c["feed_timeout_s"]=30;c["tolerance_g"]=2;c["timezone_offset_min"]=420;
  c["coarse_fine_threshold_g"]=10;
  c["pulse_step_angle"]=90;c["pulse_step_ms"]=600;
  state["events"].to<JsonArray>();state["history"].to<JsonArray>();state["schedules"].to<JsonArray>();
  state["runs"].to<JsonArray>();
  state["seq"]=0;state["last_end"]=0;state["last_scan"]=0;state["locked"]=false;
  state["overflow_count"]=0;state["overflow_reported_count"]=0;
  state["used_g"]=0;state["feed_count"]=0;state["day"]="";state["sim_bowl_g"]=0;state["sim_hopper_g"]=260;state["sim_auto"]=true;
#if WOKWI_SIM
  state["calibrated"]=true;state["offset"]=0;state["factor"]=0.42; // Wokwi 5kg: 2100 raw / 5000g
#else
  state["calibrated"]=false;state["offset"]=0;state["factor"]=1;
#endif
}
String dayKey(long epoch){
  time_t local=epoch+(long)cf("timezone_offset_min")*60;struct tm t;gmtime_r(&local,&t);
  char b[12];strftime(b,sizeof(b),"%Y-%m-%d",&t);return String(b);
}
bool ident(JsonVariantConst v){
  if(!v.is<const char*>())return false;String s=v.as<String>();if(!s.length()||s.length()>96)return false;
  for(char c:s)if(!isalnum((unsigned char)c)&&c!='_'&&c!='.'&&c!=':'&&c!='-')return false;
  return true;
}
bool numeric(JsonVariantConst v,float lo,float hi,bool integer=false){
  if(v.is<bool>()||!(v.is<int>()||v.is<long>()||v.is<float>()||v.is<double>()))return false;
  double n=v.as<double>();return isfinite(n)&&n>=lo&&n<=hi&&(!integer||floor(n)==n);
}
const char* statusVi(const char* status){
  if(!strcmp(status,"ACCEPTED"))return "Thiết bị đã nhận lệnh";
  if(!strcmp(status,"DISPENSING"))return "Đang cấp thức ăn";
  if(!strcmp(status,"SUCCESS"))return "Đã cấp đủ khẩu phần";
  if(!strcmp(status,"PARTIAL"))return "Đã cấp thiếu khẩu phần";
  if(!strcmp(status,"OVER_PORTION"))return "Đã cấp vượt khẩu phần";
  if(!strcmp(status,"REJECTED"))return "Thiết bị từ chối lệnh";
  if(!strcmp(status,"COMMAND_EXPIRED"))return "Lệnh đã hết hạn";
  if(!strcmp(status,"BLOCKED_DUPLICATE"))return "Đã chặn lệnh gửi lặp";
  if(!strcmp(status,"CONFIG_APPLIED"))return "Đã nhận cấu hình mới";
  if(!strcmp(status,"CLOCK_SYNCED"))return "Đã đồng bộ giờ từ máy chủ";
  if(!strcmp(status,"TIME_INVALID"))return "Đồng hồ thiết bị chưa khớp giờ máy chủ";
  if(!strcmp(status,"SENSOR_ERROR"))return "Cảm biến đang lỗi";
  if(!strcmp(status,"BOWL_MISSING"))return "Không phát hiện bát trên cân";
  if(!strcmp(status,"INTERRUPTED"))return "Phiên cấp bị gián đoạn";
  if(!strcmp(status,"MISSED_SCHEDULE"))return "Đã bỏ lỡ lịch cho ăn";
  if(!strcmp(status,"RECONCILED"))return "Đã gỡ khóa an toàn";
  return "Thiết bị ghi nhận sự kiện";
}
const char* errorVi(const char* code){
  if(!code)return nullptr;
  if(!strcmp(code,"TIME_INVALID"))return "Giờ ESP32 đang lệch; kiểm tra đồng bộ NTP hoặc đặt Wokwi về tốc độ 100%";
  if(!strcmp(code,"WEIGHT_DROP_DETECTED"))return "Số cân giảm bất thường khi đang cấp; servo đã dừng";
  if(!strcmp(code,"COOLDOWN"))return "Chưa hết khoảng chờ bảo vệ";
  if(!strcmp(code,"DAILY_LIMIT"))return "Đã chạm giới hạn khối lượng trong ngày";
  if(!strcmp(code,"DAILY_FEED_LIMIT"))return "Đã chạm số lần cho ăn tối đa trong ngày";
  if(!strcmp(code,"BOWL_FULL"))return "Bát không còn đủ sức chứa";
  if(!strcmp(code,"BOWL_MISSING"))return "Không phát hiện bát thức ăn";
  if(!strcmp(code,"SENSOR_ERROR"))return "Không đọc được cảm biến hoặc cân chưa ổn định";
  if(!strcmp(code,"BUSY"))return "Thiết bị đang thực hiện một phiên cấp khác";
  if(!strcmp(code,"COMMAND_EXPIRED"))return "Lệnh đã quá hạn trước khi thiết bị xử lý";
  if(!strcmp(code,"COMMAND_ID_CONFLICT"))return "Mã lệnh cũ được gửi với nội dung khác";
  if(!strcmp(code,"RECONCILIATION_REQUIRED"))return "Cần kiểm tra thiết bị trước khi tiếp tục";
  if(!strcmp(code,"INVALID_FIELD"))return "Dữ liệu lệnh không hợp lệ";
  if(!strcmp(code,"INVALID_CONFIG_OR_SCHEDULE"))return "Cấu hình hoặc lịch ăn không hợp lệ";
  if(!strcmp(code,"CONFIG_BUSY"))return "Không thể đổi cấu hình khi thiết bị đang cấp thức ăn";
  if(!strcmp(code,"OUTBOX_FULL"))return "Hàng đợi đồng bộ đang đầy; lịch và nút vật lý vẫn hoạt động";
  if(!strcmp(code,"DAILY_RESERVATION_RETAINED"))return "Hạn mức ngày vẫn được giữ để bảo vệ";
  if(!strcmp(code,"WEIGHT_UNSTABLE"))return "Cân chưa ổn định trong thời hạn cho phép";
  if(!strcmp(code,"MEASUREMENT_LOST"))return "Mất số đo cân trong phiên cấp";
  if(!strcmp(code,"POWER_RESTORED_AUTO_RESUME"))return "Có điện lại trong 1 giờ; tiếp tục phần còn thiếu";
  if(!strcmp(code,"WEIGHT_DROP_AUTO_RESUME"))return "Cân ổn định; tự tiếp tục phần còn thiếu của phiên cũ";
  if(!strcmp(code,"POWER_OUTAGE_RETRY_REQUIRED"))return "Mất điện quá 1 giờ; mở ứng dụng để xác nhận cấp lại";
  if(!strcmp(code,"RECOVERY_SCALE_UNSTABLE"))return "Cân chưa ổn định sau khi khởi động; cần kiểm tra thủ công";
  if(!strcmp(code,"FEED_TIMEOUT"))return "Đã hết thời gian cấp tối đa";
  if(!strcmp(code,"MAX_PULSES_REACHED"))return "Đã đạt số nhịp cấp tối đa";
  return "Xem mã lỗi để biết chi tiết";
}
void printEventVi(const char* status,JsonVariantConst command,const char* error){
  // A temporarily invalid boot clock is expected before NTP/server sync.
  // Keep the event in the durable outbox, but do not spam Serial Monitor.
  if(!strcmp(status,"TIME_INVALID"))return;
  Serial.printf("[SỰ KIỆN] %s (%s)",statusVi(status),status);
  if(error){Serial.printf(" — %s (%s)",errorVi(error),error);}
  if(numeric(command["target_portion_g"],0,500))Serial.printf(" — khẩu phần %.0f g",command["target_portion_g"].as<float>());
  Serial.println();
}
bool emit(const char* status,JsonVariantConst c=JsonVariantConst(),JsonVariantConst actual=JsonVariantConst(),const char* error=nullptr){
  if(strcmp(status,"ACCEPTED")&&strcmp(status,"DISPENSING"))uiStatus=error?error:status;
  if(state["events"].size()>=MAX_EVENTS){
    const bool firstOverflow=state["overflow_count"].as<unsigned long>()==0;
    state["overflow_count"]=state["overflow_count"].as<unsigned long>()+1;
    state["last_overflow_at"]=validTime()?nowSec():0;
    uiStatus="OUTBOX_FULL";if(firstOverflow)toneNotice(300);
    persist();return false;
  }
  JsonObject e=state["events"].as<JsonArray>().add<JsonObject>();
  e["v"]=1;e["device_id"]=DEVICE_ID;e["boot_id"]=bootId;
  e["event_id"]=String(DEVICE_ID)+":"+id();e["seq"]=state["seq"].as<unsigned long>()+1;state["seq"]=e["seq"];
  long occurredAt=validTime()?nowSec():0;
  if(!strcmp(status,"INTERRUPTED")&&error&&!strcmp(error,"POWER_OUTAGE_RETRY_REQUIRED")&&
     numeric(c["started_at"],1700000000,4102444800.0,true))occurredAt=c["started_at"].as<long>();
  e["occurred_at"]=occurredAt;e["status"]=status;
  if(numeric(c["delta_g"],-5000,5000))e["delta_g"]=c["delta_g"];
  if(numeric(c["current_bowl_weight_g"],0,5000))e["current_bowl_weight_g"]=c["current_bowl_weight_g"];
  if(!c.isNull() && c["command_id"].is<const char*>()){
    e["command_id"]=c["command_id"];
    if(c["source"].is<const char*>())e["source"]=c["source"];
    if(numeric(c["target_portion_g"],0,500))e["target_portion_g"]=c["target_portion_g"];
    e["actual_weight_g"].set(actual);
  }
  if(error)e["error_code"]=error;
  // The wire event stays JSON for MQTT; Serial Monitor is for people and uses Vietnamese.
  printEventVi(status,c,error);
  return persist();
}
bool emitOverflowNotice(){
  const unsigned long lost=state["overflow_count"].as<unsigned long>();
  if(lost<=state["overflow_reported_count"].as<unsigned long>()||state["events"].size()>=MAX_EVENTS)return false;
  JsonObject e=state["events"].as<JsonArray>().add<JsonObject>();
  e["v"]=1;e["device_id"]=DEVICE_ID;e["boot_id"]=bootId;
  e["event_id"]=String(DEVICE_ID)+":"+id();e["seq"]=state["seq"].as<unsigned long>()+1;state["seq"]=e["seq"];
  e["occurred_at"]=validTime()?nowSec():0;e["status"]="OUTBOX_OVERFLOW";e["overflow_count"]=lost;
  state["overflow_reported_count"]=lost;uiStatus="OUTBOX_FULL";
  return persist();
}
void event(const char* status,const char* error=nullptr){emit(status,JsonVariantConst(),JsonVariantConst(),error);}
void remember(JsonVariantConst command,const char* status,float actual,bool known=true,const char* error=nullptr){
  JsonArray h=state["history"].as<JsonArray>();JsonObject row;
  for(JsonObject old:h)if(old["command"]["command_id"]==command["command_id"]){row=old;break;}
  if(row.isNull()){
    if(h.size()>=MAX_HISTORY){
      int expired=-1;
      for(size_t i=0;i<h.size();i++)if(validTime()&&h[i]["command"]["expires_at"].as<long>()<=nowSec()){expired=(int)i;break;}
      if(expired<0){servo(false);state["locked"]=true;state["lock_reason"]="HISTORY_FULL";persist();return;}
      h.remove(expired);
    }
    row=h.add<JsonObject>();
  }
  row["command"].set(command);row["status"]=status;row["error_code"]=error;
  if(known)row["actual_weight_g"]=actual;else row["actual_weight_g"]=nullptr;
  row["seq"]=state["seq"];persist();
}
void result(JsonVariantConst c,const char* status,float actual,const char* error=nullptr,bool known=true){
  JsonDocument val;if(known)val.set(actual);
  remember(c,status,actual,known,error);
  if(storageOK)emit(status,c,val.as<JsonVariantConst>(),error);
}
void reject(JsonVariantConst c,const char* reason){result(c,!strcmp(reason,"COMMAND_EXPIRED")?reason:"REJECTED",0,reason);}
void finish(const char* status,const char* error=nullptr,bool known=true){
  servo(false);uiStatus=status;toneNotice();JsonDocument copy;copy.set(state["active"]);auto a=copy.as<JsonObject>();
  float actual=max(0.0f,weightG-a["baseline"].as<float>());
  if(known)state["used_g"]=max(0.0f,state["used_g"].as<float>()-a["target_portion_g"].as<float>()+actual);
  else{state["locked"]=true;state["lock_reason"]=error?error:status;}
  if(known)state.remove("lock_reason");
  state["active"]=nullptr;busy=false;state["last_end"]=validTime()?nowSec():state["last_end"].as<long>();
  result(a,status,actual,error,known);
}
bool commandValid(JsonVariantConst c){
  if(!c.is<JsonObjectConst>()||c.size()!=5||!ident(c["command_id"])||!c["source"].is<const char*>())return false;
  if(!((c["source"]=="APP")||(c["source"]=="SCHEDULE")||(c["source"]=="BUTTON"))||
     !numeric(c["target_portion_g"],1,cf("max_portion_g"))||!numeric(c["created_at"],1700000000,4102444800.0,true)||
     !numeric(c["expires_at"],1700000000,4102444800.0,true)||c["expires_at"].as<long>()<=c["created_at"].as<long>()||
     c["expires_at"].as<long>()-c["created_at"].as<long>()>300)return false;
  return true;
}
void receive(JsonVariantConst c){
  if(!c.is<JsonObjectConst>()||!ident(c["command_id"])){event("REJECTED","INVALID_FIELD");return;}
  for(JsonObject old:state["history"].as<JsonArray>())if(old["command"]["command_id"]==c["command_id"]){
    // Compare semantic fields, independent of JSON field order.
    for(const char* k:{"source","target_portion_g","created_at","expires_at"})if(old["command"][k]!=c[k]){event("REJECTED","COMMAND_ID_CONFLICT");return;}
    event("BLOCKED_DUPLICATE");
    JsonDocument val;val.set(old["actual_weight_g"]);emit(old["status"].as<const char*>(),c,val.as<JsonVariantConst>(),old["error_code"].as<const char*>());return;
  }
  if(!commandValid(c)){reject(c,"INVALID_FIELD");return;}
  if(!storageOK)return;
  if(!validTime()){reject(c,"TIME_INVALID");return;}
  long now=nowSec();
  if(now<c["created_at"].as<long>()-10||now<state["last_end"].as<long>()){reject(c,"TIME_INVALID");return;}
  if(now>=c["expires_at"].as<long>()){reject(c,"COMMAND_EXPIRED");return;}
  if(state["history"].size()>=MAX_HISTORY){
    bool space=false;
    for(JsonObject old:state["history"].as<JsonArray>())if(old["command"]["expires_at"].as<long>()<=now){space=true;break;}
    if(!space){event("REJECTED","HISTORY_FULL");return;}
  }
  if(state["locked"].as<bool>()){reject(c,"RECONCILIATION_REQUIRED");return;}
  if(c["source"]=="APP"&&state["events"].size()>MAX_EVENTS-6){reject(c,"OUTBOX_FULL");return;}
  if(busy){reject(c,"BUSY");return;}
  if(!state["calibrated"].as<bool>()||!weightOK||!weightFilterReady()||millis()-stableAt<700){reject(c,bowlMissing?"BOWL_MISSING":"SENSOR_ERROR");return;}
  if(now-state["last_end"].as<long>()<cf("min_interval_s")){reject(c,"COOLDOWN");return;}
  String day=dayKey(now);
  if(state["day"].as<String>()!=day){state["day"]=day;state["used_g"]=0;state["feed_count"]=0;}
  float target=c["target_portion_g"].as<float>();
  if(state["used_g"].as<float>()+target>cf("daily_limit_g")){reject(c,"DAILY_LIMIT");return;}
  if(state["feed_count"].as<int>()>=cf("max_daily_feeds")){reject(c,"DAILY_FEED_LIMIT");return;}
  if(weightG+target>cf("bowl_capacity_g")){reject(c,"BOWL_FULL");return;}
  state["active"].set(c);state["active"]["baseline"]=weightG;state["active"]["started_at"]=now;
  state["used_g"]=state["used_g"].as<float>()+target;
  state["feed_count"]=state["feed_count"].as<int>()+1;
  remember(c,"DISPENSING",0);
  if(!storageOK)return;busy=true;feedAt=millis();servoAt=millis();pulseBaseline=weightG;finePulse=target<=cf("coarse_fine_threshold_g");uiStatus="DANG CAP";servo(true);toneNotice();
  JsonDocument zero;zero.set(0);emit("ACCEPTED",c,zero.as<JsonVariantConst>());emit("DISPENSING",c,zero.as<JsonVariantConst>());
}
bool configValid(JsonVariantConst c){
  const bool legacyPulseLimit=!c["max_feed_pulses"].isNull();
  if(!c.is<JsonObjectConst>()||(c.size()!=12&&!(c.size()==13&&legacyPulseLimit)))return false;
  struct Bound{const char* key;float lo,hi;};
  Bound bs[]={{"max_portion_g",1,500},{"daily_limit_g",1,2000},{"min_interval_s",1,86400},{"command_ttl_s",5,300},
    {"feed_timeout_s",5,120},{"tolerance_g",0.1,10},{"timezone_offset_min",-720,840},
    {"bowl_capacity_g",1,5000},{"max_daily_feeds",1,100},
    {"coarse_fine_threshold_g",1,100},
    {"pulse_step_angle",1,180},{"pulse_step_ms",100,2000}};
  for(auto b:bs)if(!numeric(c[b.key],b.lo,b.hi,strcmp(b.key,"tolerance_g")!=0))return false;
  if(legacyPulseLimit&&!numeric(c["max_feed_pulses"],1,100,true))return false;
  return c["max_portion_g"].as<float>()<=c["daily_limit_g"].as<float>()&&c["tolerance_g"].as<float>()<c["max_portion_g"].as<float>();
}
bool scheduleValid(JsonVariantConst items,float maxPortion){
  if(!items.is<JsonArrayConst>()||items.size()>10)return false;
  for(JsonObjectConst s:items.as<JsonArrayConst>()){
    if(!ident(s["schedule_id"])||!numeric(s["hour"],0,23,true)||!numeric(s["minute"],0,59,true)||
      !numeric(s["target_portion_g"],1,maxPortion)||!s["enabled"].is<bool>()||!s["days"].is<JsonArrayConst>()||s["days"].size()==0||s["days"].size()>7)return false;
    int mask=0;for(JsonVariantConst d:s["days"].as<JsonArrayConst>()){
      if(!numeric(d,0,6,true)||(mask&(1<<d.as<int>())))return false;mask|=1<<d.as<int>();}
    int count=0;for(JsonObjectConst other:items.as<JsonArrayConst>())if(other["schedule_id"]==s["schedule_id"])count++;
    if(count!=1)return false;
  }return true;
}
void callback(char* topic,byte* payload,unsigned int length){
  JsonDocument d;if(deserializeJson(d,payload,length)){event("REJECTED","INVALID_JSON");return;}
  String t(topic);
  if(t==root+"/ack"){
    if(state["events"].size()&&state["events"][0]["event_id"]==d["event_id"]){
      state["events"].as<JsonArray>().remove(0);
      if(persist())emitOverflowNotice();
    }return;
  }
  if(t==root+"/command"){receive(d.as<JsonVariantConst>());return;}
  if(t==root+"/sync"){
    // Clock correction is independent of config validity: bad config must not
    // leave the device using an invalid or stale clock.
    if(numeric(d["server_time"],1700000000,4102444800.0,true)){
      const long serverTime=d["server_time"].as<long>();
      const bool clockWasValid=validTime();
      if(!clockWasValid||labs(nowSec()-serverTime)>2){
        timeval corrected{};corrected.tv_sec=serverTime;
        if(settimeofday(&corrected,nullptr)==0){
          if(recoveryPending&&state["sim_outage_s"].isNull()&&
             numeric(d["previous_device_seen_at"],1700000000,4102444800.0,true)){
            const long elapsed=serverTime-d["previous_device_seen_at"].as<long>();
            if(elapsed>=0&&elapsed<=30L*86400){state["recovery_elapsed_s"]=elapsed;persist();}
          }
          // Clock maintenance is independent of config and must not fill the durable outbox.
          if(!clockSyncReported||!clockWasValid){event("CLOCK_SYNCED");clockSyncReported=true;}
          syncTelemetryPending=true;
        }
      }else if(recoveryPending&&state["sim_outage_s"].isNull()&&state["recovery_elapsed_s"].isNull()&&
               numeric(d["previous_device_seen_at"],1700000000,4102444800.0,true)){
        const long elapsed=serverTime-d["previous_device_seen_at"].as<long>();
        if(elapsed>=0&&elapsed<=30L*86400){state["recovery_elapsed_s"]=elapsed;persist();}
      }
    }
    if(!ident(d["version"])||!configValid(d["config"])||!scheduleValid(d["schedules"],d["config"]["max_portion_g"].as<float>())){event("REJECTED","INVALID_CONFIG_OR_SCHEDULE");return;}
    const String incomingVersion=d["version"].as<String>();
    // Replays are harmless even while dispensing. A changed version with identical
    // content only updates the acknowledgement; it is not a new configuration.
    const bool sameConfig=state["config"]==d["config"]&&state["schedules"]==d["schedules"];
    if(sameConfig){
      if(state["config_version"].as<String>()!=incomingVersion){state["config_version"]=incomingVersion;persist();syncTelemetryPending=true;}
      return;
    }
    if(busy){event("REJECTED","CONFIG_BUSY");return;}
    // Keep last_scan/runs and daily reservation. A config sync never resets execution marks.
    state["config"].set(d["config"]);state["schedules"].set(d["schedules"]);state["config_version"]=incomingVersion;
    if(persist()){event("CONFIG_APPLIED");syncTelemetryPending=true;}
  }
}
void mqttCallback(MQTTClient*,char topic[],char payload[],int length){
  if(length<0)return;
  callback(topic,reinterpret_cast<byte*>(payload),static_cast<unsigned int>(length));
}
void scanSchedules(){
  if(!validTime()||busy||!storageOK)return;
  long now=nowSec(),since=state["last_scan"].as<long>();if(!since)since=now-60;if(now<since)return;
  long start=max(since,now-7*86400L),offset=(long)cf("timezone_offset_min")*60;
  long first=(start+offset)/86400*86400-offset;
  for(long midnight=first;midnight<=now;midnight+=86400){
    time_t local=midnight+offset;struct tm t;gmtime_r(&local,&t);
    for(JsonObject s:state["schedules"].as<JsonArray>()){
      if(!s["enabled"].as<bool>())continue;bool chosen=false;
      for(int day:s["days"].as<JsonArray>())if(day==t.tm_wday)chosen=true;
      long due=midnight+s["hour"].as<int>()*3600+s["minute"].as<int>()*60;
      if(!chosen||due<=since||due>now)continue;
      String key=s["schedule_id"].as<String>()+":"+dayKey(due);bool done=false;
      for(String old:state["runs"].as<JsonArray>())if(old==key)done=true;if(done)continue;
      JsonArray runs=state["runs"].as<JsonArray>();if(runs.size()>=64)runs.remove(0);runs.add(key);
      if(!persist())return;
      if(now-due>=60){event("MISSED_SCHEDULE",key.c_str());continue;}
      JsonDocument c;c["command_id"]="sch:"+key;c["source"]="SCHEDULE";c["target_portion_g"]=s["target_portion_g"];
      c["created_at"]=now;c["expires_at"]=now+(int)cf("command_ttl_s");receive(c.as<JsonVariantConst>());
    }
  }
  state["last_scan"]=now;
  if(millis()-scanSavedAt>=30000){scanSavedAt=millis();persist();}
}
void heartbeat(){
  JsonDocument h;h["device_id"]=DEVICE_ID;h["status"]=busy?"DANG CHO AN...":uiStatus;
  if(weightOK)h["bowl_weight_g"]=weightG;else h["bowl_weight_g"]=nullptr;
  if(isfinite(distanceCM)){
    h["distance_cm"]=distanceCM;
    h["food_level_percent"]=(int)constrain((1-distanceCM/TANK_HEIGHT_CM)*100,0.0f,100.0f);
  }else{h["distance_cm"]=nullptr;h["food_level_percent"]=nullptr;}
  h["sensor_mode"]=simAuto?"DEMO_AUTO":"HX711_MANUAL";h["ip"]=WiFi.localIP().toString();h["rssi"]=WiFi.RSSI();h["occurred_at"]=validTime()?nowSec():0;h["busy"]=busy;h["time_valid"]=validTime();
  if(weightOK)h["weight_g"]=weightG;else h["weight_g"]=nullptr;
  h["locked"]=state["locked"].as<bool>()||!storageOK;
  h["outbox"]=state["events"].size();h["outbox_overflow_count"]=state["overflow_count"];
  h["mode"]="ESP32";h["boot_id"]=bootId;h["config_version"]=state["config_version"];
  h["daily_dispensed_g"]=state["used_g"];h["daily_feed_count"]=state["feed_count"];
  String b;serializeJson(h,b);if(!mqtt.publish((root+"/telemetry").c_str(),b.c_str(),false,0))Serial.println("TELEMETRY_PUBLISH_FAILED");
}
void clearRecoveryMarkers(){
  state.remove("sim_outage_s");state.remove("recovery_elapsed_s");
}
void processPowerRecovery(){
  if(!recoveryPending||!storageOK||state["active"].isNull()||!validTime())return;
  const unsigned long waitLimit=(unsigned long)cf("feed_timeout_s")*1000UL;
  if(!weightOK||!weightFilterReady()||millis()-stableAt<700){
    if(millis()-recoveryPendingSince<waitLimit)return;
    JsonDocument interrupted;interrupted.set(state["active"]);
    state["active"]=nullptr;state["locked"]=true;state["lock_reason"]="RECOVERY_SCALE_UNSTABLE";state["last_end"]=nowSec();
    recoveryPending=false;clearRecoveryMarkers();uiStatus="RECOVERY_SCALE_UNSTABLE";
    result(interrupted.as<JsonVariantConst>(),"INTERRUPTED",0,"RECOVERY_SCALE_UNSTABLE",false);
    syncTelemetryPending=true;if(mqtt.connected())heartbeat();
    return;
  }

  long simulatedOutage=-1;
#if WOKWI_SIM
  if(numeric(state["sim_outage_s"],0,30L*86400,true))simulatedOutage=state["sim_outage_s"].as<long>();
#endif
  JsonDocument saved;saved.set(state["active"]);
  if(simulatedOutage>0)saved["started_at"]=nowSec()-simulatedOutage;
  JsonVariantConst command=saved.as<JsonVariantConst>();
  const float target=command["target_portion_g"].as<float>();
  const float baseline=command["baseline"].as<float>();
  const float actual=max(0.0f,weightG-baseline);
  const float tolerance=cf("tolerance_g");
  const long startedAt=command["started_at"].as<long>();

  if(actual>target+tolerance||actual>=target-tolerance){
    state["active"]=nullptr;state["locked"]=false;state["last_end"]=nowSec();
    state.remove("lock_reason");
    state["used_g"]=max(0.0f,state["used_g"].as<float>()-target+actual);
    recoveryPending=false;clearRecoveryMarkers();
    const bool over=actual>target+tolerance;
    uiStatus=over?"OVER_PORTION":"SUCCESS";result(command,over?"OVER_PORTION":"SUCCESS",actual,over?"OVER_PORTION":nullptr,true);
    syncTelemetryPending=true;if(mqtt.connected())heartbeat();
    return;
  }

  long elapsed=simulatedOutage;
  if(elapsed<0&&numeric(state["recovery_elapsed_s"],0,30L*86400,true))elapsed=state["recovery_elapsed_s"].as<long>();
  if(elapsed<0){
    const long sessionAge=nowSec()-startedAt;
    // Without a restored server timestamp, session age is a conservative upper
    // bound for the outage because the interrupted feed began before power loss.
    if(sessionAge<0)return;
    if(millis()-recoveryPendingSince<10000)return;
    elapsed=sessionAge;
  }

  const float remaining=max(0.0f,target-actual);
  const bool bowlHasRoom=weightG+remaining<=cf("bowl_capacity_g");
  const bool waitForUser=elapsed>3600||!bowlHasRoom;
  if(waitForUser){
    state["active"]=nullptr;state["locked"]=false;
    state.remove("lock_reason");
    state["last_end"]=startedAt>0?startedAt:nowSec()-3601;
    state["used_g"]=max(0.0f,state["used_g"].as<float>()-target+actual);
    recoveryPending=false;clearRecoveryMarkers();uiStatus="POWER_OUTAGE_RETRY_REQUIRED";
    result(command,"INTERRUPTED",actual,"POWER_OUTAGE_RETRY_REQUIRED",true);
    syncTelemetryPending=true;if(mqtt.connected())heartbeat();
    return;
  }

  // Continue the original session from the measured bowl weight. Preserve its
  // baseline so finish() accounts for the full amount across both attempts.
  state["locked"]=false;state.remove("lock_reason");state["active"]["started_at"]=nowSec();
  state["active"]["recovery_count"]=state["active"]["recovery_count"].as<int>()+1;
  clearRecoveryMarkers();
  if(!persist())return;
  recoveryPending=false;busy=true;feedAt=millis();servoAt=millis();pulseBaseline=weightG;
  finePulse=remaining<=cf("coarse_fine_threshold_g");uiStatus="DANG CAP";servo(true);toneNotice();
  JsonDocument measured;measured.set(actual);
  remember(command,"DISPENSING",actual);
  emit("DISPENSING",command,measured.as<JsonVariantConst>(),"POWER_RESTORED_AUTO_RESUME");
  syncTelemetryPending=true;if(mqtt.connected())heartbeat();
}
void serialCommand(String line){
  line.trim();
#if WOKWI_SIM
  if(line=="dump state"){
    if(!nvsReady){Serial.println("NVS chưa mở được.");return;}
    const String savedState=nvs.getString("state","");
    if(savedState.length())Serial.println(savedState);
    else Serial.println("NVS chưa có key state.");
    return;
  }
  if(line=="sim offline"){
    simMqttOffline=true;
    if(mqtt.connected())mqtt.disconnect();
    Serial.println("Wokwi: đã ngắt MQTT giả lập; ESP32 vẫn chạy và giữ lịch/sự kiện trong NVS.");
    return;
  }
  if(line=="sim online"){
    simMqttOffline=false;connectAt=millis()-3000UL;
    Serial.println("Wokwi: đã bật lại MQTT; đang kết nối để đồng bộ lịch và sự kiện.");
    return;
  }
  if((line=="sim auto"||line=="sim manual")&&!busy){simAuto=line=="sim auto";state["sim_auto"]=simAuto;persist();Serial.println(simAuto?"MÔ PHỎNG HX711: cân tăng theo nhịp servo; đây không phải lượng đo thật.":"CẢM BIẾN THẬT: dùng HX711/Wokwi để thay đổi số cân.");return;}
  if(line.startsWith("sim powerloss ")&&busy){
    const long seconds=line.substring(14).toInt();
    if(seconds<0||seconds>30L*86400){Serial.println("Dùng: sim powerloss 30 hoặc sim powerloss 3601 (chỉ để thử trên Wokwi). ");return;}
    servo(false);state["sim_outage_s"]=seconds;
    if(persist()){Serial.printf("Wokwi: giả lập mất điện %ld giây rồi khởi động lại...\n",seconds);delay(100);ESP.restart();}
    return;
  }
#endif
  if(line=="status"){heartbeat();Serial.printf("Trạng thái: cân=%.1f g | đã cân chỉnh=%s | giờ hợp lệ=%s | đang cấp=%s | Wi-Fi=%s | MQTT=%s | mã MQTT=%d\n",weightG,state["calibrated"].as<bool>()?"có":"không",validTime()?"có":"không",busy?"có":"không",WiFi.status()==WL_CONNECTED?"đã nối":"mất kết nối",mqtt.connected()?"đã nối":"mất kết nối",static_cast<int>(mqtt.lastError()));}
  else if(line=="tare EMPTY"&&!busy&&weightOK){state["offset"]=scale.read();state["calibrated"]=true;persist();Serial.println("ĐÃ CÂN CHỈNH: đã lưu mức cân khi bát rỗng.");}
  else if(line.startsWith("factor ")&&!busy){float factor=line.substring(7).toFloat();if(isfinite(factor)&&factor>0){state["factor"]=factor;state["calibrated"]=false;persist();Serial.println("Hãy đặt bát rỗng rồi nhập tare EMPTY để cân chỉnh.");}}
  else if(line=="reconcile CHECKED"&&!busy&&weightOK&&validTime()){
    state["locked"]=false;state.remove("lock_reason");state["last_end"]=nowSec();persist();event("RECONCILED","DAILY_RESERVATION_RETAINED");}
  else if(line.startsWith("{")){JsonDocument d;if(!deserializeJson(d,line))receive(d.as<JsonVariantConst>());else event("REJECTED","INVALID_JSON");}
  else Serial.println("Lệnh: status | dump state | sim auto | sim manual | sim offline | sim online | sim powerloss GIÂY | tare EMPTY | factor N | reconcile CHECKED | hoặc dán lệnh JSON");
}
void autoReconcileWeightDrop(unsigned long ms){
  if(busy||recoveryPending||!state["active"].isNull()||!state["locked"].as<bool>()||
     state["lock_reason"]!="WEIGHT_DROP_DETECTED"||!weightOK||bowlMissing||
     !weightFilterReady()||weightWindowCount<WEIGHT_STABILITY_SAMPLES||
     ms-stableAt<AUTO_RECONCILE_STABLE_MS||!validTime())return;

  static String reportedCommandId;
  auto reportBlocked=[&](const String& commandId,const char* message){
    if(reportedCommandId!=commandId){reportedCommandId=commandId;Serial.println(message);}
  };
  JsonObject interrupted;
  JsonArray history=state["history"].as<JsonArray>();
  for(int i=(int)history.size()-1;i>=0;i--){
    JsonObject row=history[i].as<JsonObject>();
    if(row["status"]=="INTERRUPTED"&&row["error_code"]=="WEIGHT_DROP_DETECTED"){
      interrupted=row["command"].as<JsonObject>();break;
    }
  }
  if(interrupted.isNull()){
    reportBlocked("missing","[HX711] Cân ổn định nhưng không tìm thấy phiên cũ để tiếp tục; cần kiểm tra thủ công.");
    return;
  }
  const String interruptedId=interrupted["command_id"].as<String>();
  if(!ident(interrupted["command_id"])||
     !numeric(interrupted["target_portion_g"],1,cf("max_portion_g"))||
     !numeric(interrupted["baseline"],0,5000)){
    reportBlocked(interruptedId,"[HX711] Cân ổn định nhưng dữ liệu phiên cũ không đủ tin cậy để tiếp tục; cần kiểm tra thủ công.");
    return;
  }

  const int recoveryCount=numeric(interrupted["recovery_count"],0,100,true)
      ?interrupted["recovery_count"].as<int>():0;
  if(recoveryCount>=1){
    reportBlocked(interruptedId,"[HX711] Cân đã ổn định nhưng phiên này đã tự tiếp tục một lần; cần kiểm tra thiết bị trước khi cấp tiếp.");
    return;
  }
  if(state["events"].size()>MAX_EVENTS-6){
    reportBlocked(interruptedId,"[HX711] Cân ổn định nhưng hàng đợi sự kiện gần đầy; giữ khóa an toàn để kiểm tra thủ công.");
    return;
  }

  const float target=interrupted["target_portion_g"].as<float>();
  const float baseline=interrupted["baseline"].as<float>();
  const float tolerance=cf("tolerance_g");
  const float actual=max(0.0f,weightG-baseline);
  // A settled reading below the pre-feed bowl weight can mean the bowl was
  // removed or food was taken. Keep the lock so we never top it up blindly.
  if(weightG<baseline-tolerance){
    reportBlocked(interruptedId,"[HX711] Cân ổn định nhưng khối lượng thấp hơn lúc bắt đầu; kiểm tra bát trước khi cấp tiếp.");
    return;
  }

  JsonDocument resumed;resumed.set(interrupted);
  state["active"].set(resumed);
  state["active"]["recovery_count"]=recoveryCount+1;
  state["active"]["started_at"]=nowSec();
  state["locked"]=false;state.remove("lock_reason");
  if(!persist())return;
  reportedCommandId="";
  event("RECONCILED","WEIGHT_DROP_AUTO_RESUME");

  const float remaining=max(0.0f,target-actual);
  JsonDocument measured;measured.set(actual);
  remember(state["active"],"DISPENSING",actual);
  emit("DISPENSING",state["active"],measured.as<JsonVariantConst>(),"WEIGHT_DROP_AUTO_RESUME");
  if(actual>target+tolerance){finish("OVER_PORTION","OVER_PORTION");}
  else if(actual>=target-tolerance){finish("SUCCESS");}
  else if(weightG+remaining>cf("bowl_capacity_g")){finish("PARTIAL","BOWL_FULL");}
  else{
    busy=true;feedAt=ms;servoAt=ms;pulseBaseline=weightG;
    finePulse=remaining<=cf("coarse_fine_threshold_g");
    uiStatus="DANG CAP";
    if(!persist())return;
    servo(true);toneNotice();
    Serial.printf("[HX711] Cân ổn định 2 giây; tự tiếp tục phiên cũ, còn %.1f g.\n",remaining);
  }
  syncTelemetryPending=true;
}
void setup(){
  Serial.begin(115200);bootId=id();
  // MQTT client IDs are broker-wide: separate topic namespaces must not evict
  // each other's ESP32 connection. Keep the ID stable for this logical device.
  uint32_t clientHash=2166136261u;for(char c:root+":"+DEVICE_ID){clientHash^=(uint8_t)c;clientHash*=16777619u;}
  mqttClientId=String("petfeeder-")+String(clientHash,HEX);
  ledcSetup(0,50,16);ledcAttachPin(SERVO_PIN,0);servo(false);
  pinMode(GREEN_PIN,OUTPUT);pinMode(RED_PIN,OUTPUT);pinMode(BUZZER_PIN,OUTPUT);
  Wire.begin(21,22);oledOK=display.begin(SSD1306_SWITCHCAPVCC,0x3c);
  pinMode(BUTTON_PIN,INPUT_PULLUP);pinMode(TRIG_PIN,OUTPUT);pinMode(ECHO_PIN,INPUT);scale.begin(DT_PIN,SCK_PIN);
  // LittleFS is mounted only to read the previous firmware's state.json.
  // Runtime state now lives in NVS; the legacy file is kept after migration.
#if WOKWI_SIM
  if(blankSimulationStorage()){
    Serial.println("Wokwi: đang khởi tạo phân vùng LittleFS trống để đọc dữ liệu cũ.");
    legacyFsReady=esp_littlefs_format("spiffs")==ESP_OK&&LittleFS.begin(false);
  }else legacyFsReady=LittleFS.begin(false);
#else
  legacyFsReady=LittleFS.begin(false);
#endif
  if(!legacyFsReady)Serial.println("LittleFS cũ không đọc được; NVS vẫn được dùng nếu đã có dữ liệu.");
  nvsReady=nvs.begin("petfeeder",false);
  if(!nvsReady){storageOK=false;Serial.println("LỖI NVS: không mở được phân vùng lưu trạng thái; cơ cấu cấp bị khóa.");}
  else {
    const String saved=nvs.getString("state","");
    if(saved.length()){
      if(deserializeJson(state,saved)){storageOK=false;Serial.println("LỖI NVS: dữ liệu trạng thái bị hỏng; đã khóa cơ cấu cấp.");}
      else storageOK=true;
    }else if(stateFileExists()){
      File f=LittleFS.open("/state.json","r");
      if(!f||deserializeJson(state,f)){storageOK=false;Serial.println("LỖI MIGRATION: state.json bị hỏng; dữ liệu gốc được giữ nguyên và cơ cấu cấp bị khóa.");}
      else {
        storageOK=true;
        if(persist())Serial.println("ĐÃ MIGRATE: trạng thái LittleFS đã được ghi và đọc kiểm tra trên NVS; state.json cũ được giữ lại.");
      }
      if(f)f.close();
    }else if(legacyFsReady){
      storageOK=true;defaults();persist();
    }else {
      storageOK=false;Serial.println("LỖI BỘ NHỚ: chưa có trạng thái NVS và không đọc được LittleFS. Chỉ nhập INIT_NEW_DEVICE cho thiết bị mới.");
    }
  }
  if(storageOK){
    // Keep the current policy while preserving calibration, schedules and totals.
    JsonObject c=cfg();bool changed=false;
    const char* keys[]={"max_portion_g","daily_limit_g","min_interval_s","command_ttl_s","feed_timeout_s","tolerance_g","timezone_offset_min","bowl_capacity_g","max_daily_feeds","coarse_fine_threshold_g","pulse_step_angle","pulse_step_ms"};
    const int values[]={100,200,180,60,30,2,420,150,6,10,90,600};
    for(int i=0;i<12;i++)if(c[keys[i]].isNull()){c[keys[i]]=values[i];changed=true;}
    if(!c["max_feed_pulses"].isNull()){c.remove("max_feed_pulses");changed=true;}
    if(!c["require_pet"].isNull()){c.remove("require_pet");changed=true;}
    for(const char* key:{"tank_height_cm","empty_threshold_cm","observation_s","food_stale_s","food_confirmed","food_label","lockdown","anti_jam_max_retries"})if(!c[key].isNull()){c.remove(key);changed=true;}
    for(const char* key:{"observations","food_since","stale_alert"})if(!state[key].isNull()){state.remove(key);changed=true;}
    if(state["sim_hopper_g"].isNull()){state["sim_hopper_g"]=260;changed=true;}
    if(state["events"].isNull()){state["events"].to<JsonArray>();changed=true;}
    if(state["history"].isNull()){state["history"].to<JsonArray>();changed=true;}
    if(state["schedules"].isNull()){state["schedules"].to<JsonArray>();changed=true;}
    if(state["runs"].isNull()){state["runs"].to<JsonArray>();changed=true;}
    if(state["last_end"].isNull()){state["last_end"]=0;changed=true;}
    if(state["last_scan"].isNull()){state["last_scan"]=0;changed=true;}
    if(state["seq"].isNull()){state["seq"]=0;changed=true;}
    if(state["locked"].isNull()){state["locked"]=false;changed=true;}
    // Recover the interrupted reason when upgrading older firmware. Ignore
    // rejected retries so the last completed session remains identifiable.
    if(state["locked"].as<bool>()&&state["lock_reason"].isNull()&&state["history"].size()<MAX_HISTORY){
      JsonObject lastSession;
      for(JsonObject h:state["history"].as<JsonArray>())
        if(h["status"]!="REJECTED"&&h["status"]!="COMMAND_EXPIRED")lastSession=h;
      if(!lastSession.isNull()&&lastSession["status"]=="INTERRUPTED"&&lastSession["error_code"]=="WEIGHT_DROP_DETECTED"){
        state["lock_reason"]="WEIGHT_DROP_DETECTED";changed=true;
      }
    }
    if(state["overflow_count"].isNull()){state["overflow_count"]=0;changed=true;}
    if(state["overflow_reported_count"].isNull()){state["overflow_reported_count"]=0;changed=true;}
    if(state["day"].isNull()||!state["day"].is<const char*>()||!state["day"].as<String>().length()){
      state["day"]=validTime()?dayKey(nowSec()):"";changed=true;
    }
    if(state["feed_count"].isNull()){
      int count=0;for(JsonObject h:state["history"].as<JsonArray>())
        if(h["status"]!="REJECTED"&&h["status"]!="COMMAND_EXPIRED"&&dayKey(h["command"]["created_at"].as<long>())==state["day"].as<String>())count++;
      state["feed_count"]=count;changed=true;
    }
    if(state["used_g"].isNull()){
      float total=0;for(JsonObject h:state["history"].as<JsonArray>())
        if(dayKey(h["command"]["created_at"].as<long>())==state["day"].as<String>()&&numeric(h["actual_weight_g"],0,5000))total+=h["actual_weight_g"].as<float>();
      state["used_g"]=total;changed=true;
    }
    if(changed)persist();
  }
  if(storageOK&&!state["active"].isNull()){
    recoveryPending=true;recoveryPendingSince=millis();state["locked"]=true;state["lock_reason"]="POWER_RECOVERY_PENDING";uiStatus="PHUC HOI";persist();
    Serial.println("Phát hiện phiên cấp dang dở trong NVS; chờ đồng bộ giờ và cân ổn định để phục hồi.");
  }
  #if WOKWI_SIM
  simAuto=storageOK&&state["sim_auto"].as<bool>();
#endif
  busy=false;WiFi.mode(WIFI_STA);WiFi.setAutoReconnect(true);WiFi.begin("Wokwi-GUEST","",6);configTime(0,0,"pool.ntp.org","time.google.com");
  mqtt.begin(MQTT_HOST,MQTT_PORT,wifiClient);mqtt.onMessageAdvanced(mqttCallback);mqtt.setTimeout(1000);mqtt.setKeepAlive(60);
  Serial.printf("Đang kết nối Wi-Fi Wokwi-GUEST và MQTT %s:%d. Topic: %s | Client: %s\n",MQTT_HOST,MQTT_PORT,root.c_str(),mqttClientId.c_str());
  Serial.println("PetFeeder đã sẵn sàng. Lệnh: status | dump state | sim manual | sim auto | sim offline | sim online. Cân HX711 không tự chỉnh về 0 khi khởi động.");
}
void loop(){
  while(Serial.available()){
    char c=Serial.read();if(c=='\n'||c=='\r'){
      if(!serialLine.length())continue; // Accept CR, LF and CRLF without repeating a command.
      Serial.println();serialLine.trim();
      if(serialLine=="INIT_NEW_DEVICE"&&!storageOK){
        if(!nvsReady)nvsReady=nvs.begin("petfeeder",false);
        if(nvsReady&&nvs.clear()){state.clear();storageOK=true;defaults();persist();
#if WOKWI_SIM
        simAuto=true;
#endif
        Serial.println("ĐÃ KHỞI TẠO: chỉ dùng cho thiết bị mới chưa có dữ liệu.");}
      }else if(storageOK)serialCommand(serialLine);serialLine="";
    }else if(c=='\b'||c==127){
      if(serialLine.length()){serialLine.remove(serialLine.length()-1);Serial.print("\b \b");}
    }else if(static_cast<uint8_t>(c)>=32&&serialLine.length()<4096){serialLine+=c;Serial.write(c);}
  }
  unsigned long ms=millis();
  updatePanel();
  if(!storageOK){servo(false);delay(1);return;}
  weightDropped=false;
  if(ms-hopperAt>=500){
    hopperAt=ms;
#if WOKWI_SIM
    if(simAuto){
      float hopperG=constrain(state["sim_hopper_g"].as<float>(),0.0f,HOPPER_CAPACITY_G);
      distanceCM=TANK_HEIGHT_CM*(1-hopperG/HOPPER_CAPACITY_G);
    }else
#endif
    {
      distanceCM=NAN;
      for(int attempt=0;attempt<3;attempt++){
        digitalWrite(TRIG_PIN,LOW);delayMicroseconds(2);digitalWrite(TRIG_PIN,HIGH);delayMicroseconds(10);digitalWrite(TRIG_PIN,LOW);
        unsigned long echo=pulseIn(ECHO_PIN,HIGH,25000);
        if(echo){distanceCM=echo/58.0f;break;}
      }
    }
  }
  if(ms-sampleAt>=100){
    sampleAt=ms;
    #if WOKWI_SIM
    if(simAuto){
      if(busy&&motorOpen&&ms-servoAt>=(finePulse?150:cf("pulse_step_ms")-50)){
        float remaining=state["active"]["target_portion_g"].as<float>()-(state["sim_bowl_g"].as<float>()-state["active"]["baseline"].as<float>());
        float gain=max(0.0f,min(finePulse?2.5f:5.0f,remaining));
        if(gain>0){state["sim_bowl_g"]=state["sim_bowl_g"].as<float>()+gain;state["sim_hopper_g"]=max(0.0f,state["sim_hopper_g"].as<float>()-gain);servo(false);persist();Serial.printf("MÔ PHỎNG: lượng cân tăng %.1f g (số liệu giả lập).\n",gain);}
      }
      float w=state["sim_bowl_g"].as<float>();weightOK=isfinite(w);bowlMissing=false;
      if(weightOK)trackWeight(w,ms);else resetWeightFilter(ms);
    }else
#endif
    if(scale.is_ready()){
      float w=(scale.read()-state["offset"].as<long>())/state["factor"].as<float>();
      // Proxy only: removing a bowl that was present during tare drives HX711 negative.
      bowlMissing=isfinite(w)&&w<=-10;weightOK=isfinite(w)&&w>=-2&&w<=5000;
      if(weightOK)trackWeight(max(0.0f,w),ms);else resetWeightFilter(ms);
    }else if(ms-lastWeightAt>=1000&&weightOK){weightOK=false;resetWeightFilter(ms);}
  }
  autoReconcileWeightDrop(ms);
  if(busy){
    if(state["locked"].as<bool>())finish("INTERRUPTED","RECONCILIATION_REQUIRED",false);
    else if(!weightOK)finish(bowlMissing?"BOWL_MISSING":"SENSOR_ERROR",bowlMissing?"BOWL_MISSING":"MEASUREMENT_LOST",false);
    else{
      float actual=weightG-state["active"]["baseline"].as<float>(),target=state["active"]["target_portion_g"].as<float>();
      if(weightDropped)finish("INTERRUPTED","WEIGHT_DROP_DETECTED",false);
      else if(!weightFilterReady()||ms-stableAt<700){
        if(motorOpen){servo(false);servoAt=ms;}
        if(ms-feedAt>=(unsigned long)(cf("feed_timeout_s")*1000))finish("SENSOR_ERROR","WEIGHT_UNSTABLE",false);
      }
      else if(actual>target+cf("tolerance_g"))finish("OVER_PORTION","OVER_PORTION");
      else if(actual>0&&actual>=target-cf("tolerance_g")){servo(false);finish("SUCCESS");}
      else if(ms-feedAt>=(unsigned long)(cf("feed_timeout_s")*1000))finish(actual>0?"PARTIAL":"TIMEOUT","FEED_TIMEOUT");
      else if(motorOpen){
        if(ms-servoAt>=(finePulse?200:cf("pulse_step_ms"))){servo(false);servoAt=ms;}
      }else if(ms-servoAt>=600){
        if(weightG-pulseBaseline>=1)finePulse=target-actual<=cf("coarse_fine_threshold_g");
        pulseBaseline=weightG;servoAt=ms;servo(true);
      }
    }
  }
  if(WiFi.status()==WL_CONNECTED){
    if(!mqtt.connected()
#if WOKWI_SIM
       &&!simMqttOffline
#endif
       &&!busy&&ms-connectAt>=3000){connectAt=ms;
      if(mqtt.connect(mqttClientId.c_str(),MQTT_USER,MQTT_PASS)){
        Serial.printf("Đã kết nối MQTT tới %s:%d.\n",MQTT_HOST,MQTT_PORT);
        mqtt.subscribe((root+"/command").c_str(),1);mqtt.subscribe((root+"/sync").c_str(),1);mqtt.subscribe((root+"/ack").c_str(),1);beatAt=ms;heartbeat();
      }
    }
    if(mqtt.connected()){
      mqtt.loop();
      if(syncTelemetryPending||ms-beatAt>=5000){syncTelemetryPending=false;beatAt=ms;heartbeat();}
      if(!busy&&ms-publishAt>=1000&&state["events"].size()){
        publishAt=ms;String e;serializeJson(state["events"][0],e);
        if(!mqtt.publish((root+"/events").c_str(),e.c_str(),false,1))Serial.println("EVENT_MQTT_QOS1_FAILED; giữ sự kiện trong NVS để gửi lại.");
      }
    }
  }
  processPowerRecovery();
  if(ms-scanAt>=1000){
    scanAt=ms;scanSchedules();
    static bool invalidReported=false;
    if(!validTime()&&!invalidReported){invalidReported=true;event("TIME_INVALID");}
  }
  static bool wasDown=false;static unsigned long pressedAt=0;
  bool down=digitalRead(BUTTON_PIN)==LOW;
  if(down&&!wasDown&&ms-pressedAt>100){pressedAt=ms;if(!validTime()){event("TIME_INVALID");wasDown=down;return;}JsonDocument c;c["command_id"]="btn:"+id();c["source"]="BUTTON";
    c["target_portion_g"]=20;c["created_at"]=nowSec();c["expires_at"]=nowSec()+(int)cf("command_ttl_s");receive(c.as<JsonVariantConst>());}
  wasDown=down;delay(1);
}
