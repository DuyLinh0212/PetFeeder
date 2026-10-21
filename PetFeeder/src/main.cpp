// Main circuit by Danh, extended with Long's persistent command/schedule controller.
// One ESP32, both original servos, OLED, LEDs, buzzer and the original pin mapping.
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <esp_partition.h>
#if WOKWI_SIM
#include <esp_littlefs.h>
#endif
#include <HX711.h>
#include <time.h>
#include <sys/time.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#if __has_include("secrets.h")
#include "secrets.h"
#else
#include "secrets.example.h"
#endif

constexpr int SERVO_PIN=13, ANTI_PIN=12, BUTTON_PIN=4, DT_PIN=19, SCK_PIN=23;
constexpr int TRIG_PIN=5, ECHO_PIN=18, GREEN_PIN=2, RED_PIN=15, BUZZER_PIN=14;
Adafruit_SSD1306 display(128,64,&Wire,-1);
bool oledOK=false,simAuto=false,simJam=false;
float distanceCM=12,pulseBaseline=0;
unsigned long distanceAt=0,displayAt=0,antiAt=0,buzzUntil=0;
int jamRetries=0,antiStep=0,pulseCount=0;
bool finePulse=false,bowlMissing=false,weightDropped=false;
bool idleWeightKnown=false;
float idleWeight=0;
String uiStatus="KHOI DONG";
void toneNotice(unsigned long duration=100){digitalWrite(BUZZER_PIN,HIGH);buzzUntil=millis()+duration;}
void antiServo(int angle){ledcWrite(1,(uint32_t)((500+angle*2000/180)*65535UL/20000));}
void servoAngle(int angle){ledcWrite(0,(uint32_t)((500+angle*2000/180)*65535UL/20000));}
constexpr size_t MAX_EVENTS=96, MAX_HISTORY=32;
WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
HX711 scale;
JsonDocument state;
bool storageOK=false,weightOK=false,busy=false,motorOpen=false;
float weightG=0,lastSample=0;
float weightWindow[5]={0};int weightWindowCount=0,weightWindowIndex=0;
unsigned long lastWeightAt=0;
unsigned long sampleAt=0,stableAt=0,beatAt=0,publishAt=0,connectAt=0,scanAt=0;
unsigned long feedAt=0,servoAt=0;
unsigned long scanSavedAt=0;
String serialLine;
String bootId;
String root=MQTT_TOPIC_PREFIX;
bool validTime(){return time(nullptr)>1700000000;}
long nowSec(){return (long)time(nullptr);}
void servo(bool open){motorOpen=open;servoAngle(open?(finePulse?60:state["config"]["pulse_step_angle"].as<int>()):0);}
void updatePanel(){
  digitalWrite(GREEN_PIN,busy&&!antiStep);
  digitalWrite(RED_PIN,!storageOK||state["locked"].as<bool>()||antiStep||uiStatus=="JAM_ERROR");
  if(buzzUntil&&(long)(millis()-buzzUntil)>=0){digitalWrite(BUZZER_PIN,LOW);buzzUntil=0;}
  if(!oledOK||millis()-displayAt<500)return;displayAt=millis();
  display.clearDisplay();display.setTextColor(SSD1306_WHITE);display.setTextSize(1);display.setCursor(0,0);
  display.println("PETFEEDER NHOM 7");display.print("Hat: ");if(isfinite(distanceCM)&&storageOK)display.print((int)constrain((1-distanceCM/state["config"]["tank_height_cm"].as<float>())*100,0.0f,100.0f));else display.print("?");display.println("%");
  display.print("Bat: ");if(weightOK)display.print(weightG,1);else display.print("?");display.println(" g");
  display.print("TT: ");display.println(!storageOK?"STORAGE LOCK":busy?(antiStep?"GO KET":"DANG CAP"):uiStatus);
  display.print("MQTT: ");display.println(mqtt.connected()?"ON":"OFF");
  display.print(simAuto?"DEMO AUTO":"HX711 MANUAL");display.display();
}

bool persist(){
  if(!storageOK)return false;
  File f=LittleFS.open("/state.tmp","w");
  if(!f)return storageOK=false;
  const size_t expected=measureJson(state),written=serializeJson(state,f);
  f.flush();f.close();
  if(written!=expected || !LittleFS.rename("/state.tmp","/state.json")){
    servo(false);storageOK=false;Serial.println("LỖI: Không lưu được trạng thái; đã khóa cơ cấu cấp để bảo vệ.");return false;
  }
  return true;
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
void trackWeight(unsigned long ms){
  weightDropped=busy&&weightG-lastSample < -2;
  weightWindow[weightWindowIndex++%5]=weightG;if(weightWindowCount<5)weightWindowCount++;
  float lo=weightG,hi=weightG;for(int i=0;i<weightWindowCount;i++){lo=min(lo,weightWindow[i]);hi=max(hi,weightWindow[i]);}
  if(weightWindowCount<5||hi-lo>cf("tolerance_g"))stableAt=ms;
  lastSample=weightG;lastWeightAt=ms;
}
String id(){char b[17];snprintf(b,sizeof(b),"%08lx%08lx",(unsigned long)esp_random(),(unsigned long)esp_random());return String(b);}
void defaults(){
  JsonObject c=state["config"].to<JsonObject>();
  c["max_portion_g"]=100;c["daily_limit_g"]=200;c["min_interval_s"]=180;
  c["tank_height_cm"]=25;c["empty_threshold_cm"]=20;
  c["observation_s"]=60;c["food_stale_s"]=3600;c["command_ttl_s"]=60;
  c["feed_timeout_s"]=30;c["tolerance_g"]=2;c["timezone_offset_min"]=420;
  c["require_pet"]=false;c["food_confirmed"]=false;c["food_label"]="";c["lockdown"]=false;
  c["bowl_capacity_g"]=150;c["max_daily_feeds"]=6;c["max_feed_pulses"]=15;
  c["coarse_fine_threshold_g"]=10;c["anti_jam_max_retries"]=3;
  c["pulse_step_angle"]=90;c["pulse_step_ms"]=600;
  state["events"].to<JsonArray>();state["history"].to<JsonArray>();state["schedules"].to<JsonArray>();
  state["runs"].to<JsonArray>();state["observations"].to<JsonArray>();
  state["seq"]=0;state["last_end"]=0;state["last_scan"]=0;state["locked"]=false;
  state["used_g"]=0;state["feed_count"]=0;state["day"]="";state["food_since"]=0;state["sim_bowl_g"]=0;state["sim_hopper_g"]=260;state["sim_auto"]=true;
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
  if(!strcmp(status,"JAM_ERROR"))return "Phát hiện kẹt thức ăn";
  if(!strcmp(status,"SENSOR_ERROR"))return "Cảm biến đang lỗi";
  if(!strcmp(status,"INTERRUPTED"))return "Phiên cấp bị gián đoạn";
  if(!strcmp(status,"MANUAL_REFILL"))return "Đã phát hiện thêm thức ăn vào bát";
  if(!strcmp(status,"WEIGHT_DECREASED"))return "Khối lượng bát đã giảm";
  if(!strcmp(status,"FOOD_LEFT"))return "Thức ăn vẫn còn trong bát";
  if(!strcmp(status,"FOOD_STALE"))return "Thức ăn trong bát đã để lâu";
  if(!strcmp(status,"MISSED_SCHEDULE"))return "Đã bỏ lỡ lịch cho ăn";
  if(!strcmp(status,"RECONCILED"))return "Đã xác nhận kiểm tra thiết bị";
  if(!strcmp(status,"OWNER_FOOD_CONFIRMED"))return "Chủ nuôi đã xác nhận loại thức ăn";
  return "Thiết bị ghi nhận sự kiện";
}
const char* errorVi(const char* code){
  if(!code)return nullptr;
  if(!strcmp(code,"TIME_INVALID"))return "Giờ ESP32 đang lệch; kiểm tra đồng bộ NTP hoặc đặt Wokwi về tốc độ 100%";
  if(!strcmp(code,"UNKNOWN_PET"))return "Chưa xác nhận thú cưng";
  if(!strcmp(code,"UNVERIFIED"))return "Chưa xác nhận loại thức ăn trong Cài đặt";
  if(!strcmp(code,"COOLDOWN"))return "Chưa hết khoảng chờ bảo vệ";
  if(!strcmp(code,"DAILY_LIMIT"))return "Đã chạm giới hạn khối lượng trong ngày";
  if(!strcmp(code,"DAILY_FEED_LIMIT"))return "Đã chạm số lần cho ăn tối đa trong ngày";
  if(!strcmp(code,"BOWL_FULL"))return "Bát không còn đủ sức chứa";
  if(!strcmp(code,"FOOD_EMPTY"))return "Hộp thức ăn gần hết hoặc đã hết";
  if(!strcmp(code,"BOWL_MISSING"))return "Không phát hiện bát thức ăn";
  if(!strcmp(code,"SENSOR_ERROR"))return "Không đọc được cảm biến hoặc cân chưa ổn định";
  if(!strcmp(code,"BUSY"))return "Thiết bị đang thực hiện một phiên cấp khác";
  if(!strcmp(code,"COMMAND_EXPIRED"))return "Lệnh đã quá hạn trước khi thiết bị xử lý";
  if(!strcmp(code,"OVERRIDE_NOT_SUPPORTED"))return "Không hỗ trợ bỏ qua kiểm tra an toàn";
  if(!strcmp(code,"COMMAND_ID_CONFLICT"))return "Mã lệnh cũ được gửi với nội dung khác";
  if(!strcmp(code,"RECONCILIATION_REQUIRED"))return "Cần kiểm tra thiết bị trước khi tiếp tục";
  if(!strcmp(code,"SAFETY_LOCKOUT"))return "Thiết bị đang khóa an toàn";
  if(!strcmp(code,"INVALID_REMAINDER"))return "Khẩu phần cấp bù không hợp lệ";
  if(!strcmp(code,"REMAINDER_ALREADY_REQUESTED"))return "Khẩu phần này đã có yêu cầu cấp bù";
  if(!strcmp(code,"INVALID_FIELD"))return "Dữ liệu lệnh không hợp lệ";
  if(!strcmp(code,"INVALID_CONFIG_OR_SCHEDULE"))return "Cấu hình hoặc lịch ăn không hợp lệ";
  if(!strcmp(code,"CONFIG_BUSY"))return "Không thể đổi cấu hình khi thiết bị đang cấp thức ăn";
  if(!strcmp(code,"OWNER_REFILL"))return "Đã ghi nhận chủ nuôi thêm thức ăn";
  if(!strcmp(code,"UNKNOWN_CAUSE"))return "Chưa xác định nguyên nhân thay đổi khối lượng";
  if(!strcmp(code,"DAILY_RESERVATION_RETAINED"))return "Hạn mức ngày vẫn được giữ để bảo vệ";
  return "Xem mã lỗi để biết chi tiết";
}
void printEventVi(const char* status,JsonVariantConst command,const char* error){
  Serial.printf("[SỰ KIỆN] %s (%s)",statusVi(status),status);
  if(error){Serial.printf(" — %s (%s)",errorVi(error),error);}
  if(numeric(command["target_portion_g"],0,500))Serial.printf(" — khẩu phần %.0f g",command["target_portion_g"].as<float>());
  Serial.println();
}
bool emit(const char* status,JsonVariantConst c=JsonVariantConst(),JsonVariantConst actual=JsonVariantConst(),const char* error=nullptr){
  if(strcmp(status,"ACCEPTED")&&strcmp(status,"DISPENSING"))uiStatus=error?error:status;
  if(state["events"].size()>=MAX_EVENTS){servo(false);state["locked"]=true;persist();return false;}
  JsonObject e=state["events"].as<JsonArray>().add<JsonObject>();
  e["event_id"]=String(DEVICE_ID)+":"+id();e["seq"]=state["seq"].as<unsigned long>()+1;state["seq"]=e["seq"];
  e["occurred_at"]=validTime()?nowSec():0;e["status"]=status;
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
void event(const char* status,const char* error=nullptr){emit(status,JsonVariantConst(),JsonVariantConst(),error);}
void remember(JsonVariantConst command,const char* status,float actual,bool known=true,const char* error=nullptr){
  JsonArray h=state["history"].as<JsonArray>();JsonObject row;
  for(JsonObject old:h)if(old["command"]["command_id"]==command["command_id"]){row=old;break;}
  if(row.isNull()){
    if(h.size()>=MAX_HISTORY){
      int expired=-1;
      for(size_t i=0;i<h.size();i++)if(validTime()&&h[i]["command"]["expires_at"].as<long>()<=nowSec()){expired=(int)i;break;}
      if(expired<0){servo(false);state["locked"]=true;persist();return;}
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
  servo(false);antiServo(90);antiStep=0;uiStatus=status;toneNotice();JsonDocument copy;copy.set(state["active"]);auto a=copy.as<JsonObject>();
  float actual=max(0.0f,weightG-a["baseline"].as<float>());
  if(known)state["used_g"]=max(0.0f,state["used_g"].as<float>()-a["target_portion_g"].as<float>()+actual);
  else state["locked"]=true;
  state["active"]=nullptr;busy=false;state["last_end"]=validTime()?nowSec():state["last_end"].as<long>();
  idleWeight=weightG;idleWeightKnown=known;
  if(known&&actual>0&&state["observations"].size()<8){auto o=state["observations"].as<JsonArray>().add<JsonObject>();
    o["command_id"]=a["command_id"];o["at"]=nowSec();o["baseline"]=weightG;}
  result(a,status,actual,error,known);
}
bool commandValid(JsonVariantConst c){
  return c.is<JsonObjectConst>()&&ident(c["command_id"])&&c["source"].is<const char*>()&&
    (c["source"]=="APP"||c["source"]=="SCHEDULE"||c["source"]=="BUTTON")&&
    numeric(c["target_portion_g"],1,cf("max_portion_g"))&&numeric(c["created_at"],1700000000,4102444800.0,true)&&
    numeric(c["expires_at"],1700000000,4102444800.0,true)&&c["override"].is<bool>()&&!c["override"].as<bool>()&&
    (c["retry_of"].isNull()||ident(c["retry_of"]))&&
    c["expires_at"].as<long>()>c["created_at"].as<long>()&&c["expires_at"].as<long>()-c["created_at"].as<long>()<=300;
}
void receive(JsonVariantConst c){
  if(!c.is<JsonObjectConst>()||!ident(c["command_id"])){event("REJECTED","INVALID_FIELD");return;}
  for(JsonObject old:state["history"].as<JsonArray>())if(old["command"]["command_id"]==c["command_id"]){
    String before,after;serializeJson(old["command"],before);serializeJson(c,after);
    // Compare semantic fields, independent of JSON field order.
    for(const char* k:{"source","target_portion_g","created_at","expires_at","override","retry_of"})if(old["command"][k]!=c[k]){event("REJECTED","COMMAND_ID_CONFLICT");return;}
    event("BLOCKED_DUPLICATE");
    JsonDocument val;val.set(old["actual_weight_g"]);emit(old["status"].as<const char*>(),c,val.as<JsonVariantConst>(),old["error_code"].as<const char*>());return;
  }
  if(!commandValid(c)){reject(c,c["override"].is<bool>()&&c["override"].as<bool>()?"OVERRIDE_NOT_SUPPORTED":"INVALID_FIELD");return;}
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
  if(state["locked"].as<bool>()||state["events"].size()>MAX_EVENTS-6){reject(c,"RECONCILIATION_REQUIRED");return;}
  if(busy){reject(c,"BUSY");return;}
  if(cfg()["lockdown"].as<bool>()){reject(c,"SAFETY_LOCKOUT");return;}
  if(cfg()["require_pet"].as<bool>()){reject(c,"UNKNOWN_PET");return;}
  if(!cfg()["food_confirmed"].as<bool>()){reject(c,"UNVERIFIED");return;}
  if(!state["calibrated"].as<bool>()||!weightOK||millis()-stableAt<700){reject(c,bowlMissing?"BOWL_MISSING":"SENSOR_ERROR");return;}
  if(now-state["last_end"].as<long>()<cf("min_interval_s")){reject(c,"COOLDOWN");return;}
  String day=dayKey(now);
  if(state["day"].as<String>()!=day){state["day"]=day;state["used_g"]=0;state["feed_count"]=0;}
  float target=c["target_portion_g"].as<float>();
  if(state["used_g"].as<float>()+target>cf("daily_limit_g")){reject(c,"DAILY_LIMIT");return;}
  if(state["feed_count"].as<int>()>=cf("max_daily_feeds")){reject(c,"DAILY_FEED_LIMIT");return;}
  if(weightG+target>cf("bowl_capacity_g")){reject(c,"BOWL_FULL");return;}
  if(!isfinite(distanceCM)){reject(c,"SENSOR_ERROR");return;}
  if(distanceCM>=cf("empty_threshold_cm")){reject(c,"FOOD_EMPTY");return;}
  if(!c["retry_of"].isNull()){
    JsonObject parent;
    for(JsonObject h:state["history"].as<JsonArray>())if(h["command"]["command_id"]==c["retry_of"]){parent=h;break;}
    if(parent.isNull()||!(parent["status"]=="PARTIAL"||parent["status"]=="JAM_ERROR"||parent["status"]=="TIMEOUT")||
       parent["actual_weight_g"].isNull()||fabs(parent["command"]["target_portion_g"].as<float>()-parent["actual_weight_g"].as<float>()-target)>0.01){reject(c,"INVALID_REMAINDER");return;}
    if(!parent["remainder_id"].isNull()){reject(c,"REMAINDER_ALREADY_REQUESTED");return;}
    parent["remainder_id"]=c["command_id"];
  }
  state["active"].set(c);state["active"]["baseline"]=weightG;state["active"]["started_at"]=now;
  state["used_g"]=state["used_g"].as<float>()+target;
  state["feed_count"]=state["feed_count"].as<int>()+1;
  remember(c,"DISPENSING",0);
  if(!storageOK)return;busy=true;feedAt=millis();servoAt=millis();pulseBaseline=weightG;jamRetries=0;antiStep=0;pulseCount=1;finePulse=target<=cf("coarse_fine_threshold_g");uiStatus="DANG CAP";servo(true);toneNotice();
  JsonDocument zero;zero.set(0);emit("ACCEPTED",c,zero.as<JsonVariantConst>());emit("DISPENSING",c,zero.as<JsonVariantConst>());
}
bool configValid(JsonVariantConst c){
  if(!c.is<JsonObjectConst>())return false;
  struct Bound{const char* key;float lo,hi;};
  Bound bs[]={{"tank_height_cm",5,100},{"empty_threshold_cm",2,100},{"max_portion_g",1,500},{"daily_limit_g",1,2000},{"min_interval_s",1,86400},
    {"observation_s",5,86400},{"food_stale_s",5,604800},{"command_ttl_s",5,300},
    {"feed_timeout_s",5,120},{"tolerance_g",0.1,10},{"timezone_offset_min",-720,840},
    {"bowl_capacity_g",1,5000},{"max_daily_feeds",1,100},{"max_feed_pulses",1,100},
    {"coarse_fine_threshold_g",1,100},{"anti_jam_max_retries",1,10},
    {"pulse_step_angle",1,180},{"pulse_step_ms",100,2000}};
  for(auto b:bs)if(!numeric(c[b.key],b.lo,b.hi,strcmp(b.key,"tolerance_g")!=0))return false;
  return c["lockdown"].is<bool>()&&c["require_pet"].is<bool>()&&c["food_confirmed"].is<bool>()&&c["food_label"].is<const char*>()&&
    strlen(c["food_label"].as<const char*>())<=80&&(!c["food_confirmed"].as<bool>()||strlen(c["food_label"].as<const char*>())>0)&&
    c["empty_threshold_cm"].as<float>()<=c["tank_height_cm"].as<float>()&&
    c["max_portion_g"].as<float>()<=c["daily_limit_g"].as<float>()&&c["tolerance_g"].as<float>()<c["max_portion_g"].as<float>();
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
    if(state["events"].size()&&state["events"][0]["event_id"]==d["event_id"]){state["events"].as<JsonArray>().remove(0);persist();}return;
  }
  if(t==root+"/command"){receive(d.as<JsonVariantConst>());return;}
  if(t==root+"/sync"){
    if(numeric(d["server_time"],1700000000,4102444800.0,true)){
      const long serverTime=d["server_time"].as<long>();
      if(!validTime()||labs(nowSec()-serverTime)>2){
        timeval corrected{};corrected.tv_sec=serverTime;
        if(settimeofday(&corrected,nullptr)==0)event("CLOCK_SYNCED");
      }
    }
    if(!configValid(d["config"])||!scheduleValid(d["schedules"],d["config"]["max_portion_g"].as<float>())){event("REJECTED","INVALID_CONFIG_OR_SCHEDULE");return;}
    if(busy){if(d["config"]["lockdown"].as<bool>()){cfg()["lockdown"]=true;persist();}event("REJECTED","CONFIG_BUSY");return;}
    const String incomingVersion=d["version"].as<String>();
    if(incomingVersion.length()&&state["config_version"].as<String>()==incomingVersion)return;
    // Keep last_scan/runs and daily reservation. A config sync never resets execution marks.
    state["config"].set(d["config"]);state["schedules"].set(d["schedules"]);state["config_version"]=d["version"];persist();event("CONFIG_APPLIED");
  }
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
      c["created_at"]=now;c["expires_at"]=now+(int)cf("command_ttl_s");c["override"]=false;receive(c.as<JsonVariantConst>());
    }
  }
  state["last_scan"]=now;
  if(millis()-scanSavedAt>=30000){scanSavedAt=millis();persist();}
}
void heartbeat(){
  JsonDocument h;h["device_id"]=DEVICE_ID;h["status"]=busy?"DANG CHO AN...":uiStatus;
  if(isfinite(distanceCM)){h["distance_cm"]=distanceCM;h["food_level_percent"]=(int)constrain((1-distanceCM/cf("tank_height_cm"))*100,0.0f,100.0f);}else{h["distance_cm"]=nullptr;h["food_level_percent"]=nullptr;}
  if(weightOK)h["bowl_weight_g"]=weightG;else h["bowl_weight_g"]=nullptr;
  h["sensor_mode"]=simAuto?"DEMO_AUTO":"HX711_MANUAL";h["ip"]=WiFi.localIP().toString();h["rssi"]=WiFi.RSSI();h["occurred_at"]=validTime()?nowSec():0;h["busy"]=busy;h["time_valid"]=validTime();
  if(weightOK)h["weight_g"]=weightG;else h["weight_g"]=nullptr;
  h["locked"]=state["locked"].as<bool>()||!storageOK;h["food_since"]=state["food_since"];
  h["outbox"]=state["events"].size();h["mode"]="ESP32";h["boot_id"]=bootId;h["config_version"]=state["config_version"];
  h["daily_dispensed_g"]=state["used_g"];h["daily_feed_count"]=state["feed_count"];
  String b;serializeJson(h,b);if(!mqtt.publish((root+"/telemetry").c_str(),b.c_str(),false))Serial.println("TELEMETRY_PUBLISH_FAILED");
}
void serialCommand(String line){
  line.trim();
#if WOKWI_SIM
  if((line=="sim auto"||line=="sim manual")&&!busy){simAuto=line=="sim auto";state["sim_auto"]=simAuto;persist();Serial.println(simAuto?"MÔ PHỎNG: tự thay đổi số cân; đây không phải lượng thức ăn đo thật.":"CẢM BIẾN THẬT: thay đổi HX711 và HC-SR04 bằng tay trong Wokwi.");return;}
  if((line=="sim jam on"||line=="sim jam off")&&!busy){simJam=line=="sim jam on";return;}
  if(line=="sim empty"&&!busy&&simAuto){state["sim_bowl_g"]=0;persist();return;}
#endif
  if(line=="status"){heartbeat();Serial.printf("Trạng thái: cân=%.1f g | đã cân chỉnh=%s | giờ hợp lệ=%s | đang cấp=%s | Wi-Fi=%s | MQTT=%s | mã MQTT=%d\n",weightG,state["calibrated"].as<bool>()?"có":"không",validTime()?"có":"không",busy?"có":"không",WiFi.status()==WL_CONNECTED?"đã nối":"mất kết nối",mqtt.connected()?"đã nối":"mất kết nối",mqtt.state());}
  else if(line=="tare EMPTY"&&!busy&&weightOK){state["offset"]=scale.read();state["calibrated"]=true;persist();Serial.println("ĐÃ CÂN CHỈNH: đã lưu mức cân khi bát rỗng.");}
  else if(line.startsWith("factor ")&&!busy){float factor=line.substring(7).toFloat();if(isfinite(factor)&&factor>0){state["factor"]=factor;state["calibrated"]=false;persist();Serial.println("Hãy đặt bát rỗng rồi nhập tare EMPTY để cân chỉnh.");}}
  else if(line=="reconcile CHECKED"&&!busy&&weightOK&&validTime()){
    state["locked"]=false;state["last_end"]=nowSec();persist();event("RECONCILED","DAILY_RESERVATION_RETAINED");}
  else if(line=="food CONFIRMED"&&!busy){cfg()["food_confirmed"]=true;cfg()["food_label"]="Chu xac nhan qua Serial";persist();event("OWNER_FOOD_CONFIRMED");}
  else if(line.startsWith("{")){JsonDocument d;if(!deserializeJson(d,line))receive(d.as<JsonVariantConst>());else event("REJECTED","INVALID_JSON");}
  else Serial.println("Lệnh: status | food CONFIRMED | tare EMPTY | factor N | reconcile CHECKED | hoặc dán lệnh JSON");
}
void setup(){
  Serial.begin(115200);bootId=id();ledcSetup(0,50,16);ledcAttachPin(SERVO_PIN,0);servo(false);
  ledcSetup(1,50,16);ledcAttachPin(ANTI_PIN,1);antiServo(90);
  pinMode(GREEN_PIN,OUTPUT);pinMode(RED_PIN,OUTPUT);pinMode(BUZZER_PIN,OUTPUT);
  Wire.begin(21,22);oledOK=display.begin(SSD1306_SWITCHCAPVCC,0x3c);
  pinMode(BUTTON_PIN,INPUT_PULLUP);pinMode(TRIG_PIN,OUTPUT);pinMode(ECHO_PIN,INPUT);scale.begin(DT_PIN,SCK_PIN);
  // Only a fully erased Wokwi partition may be initialized automatically.
  // Existing data and real hardware must never be formatted on a mount failure.
#if WOKWI_SIM
  if(blankSimulationStorage()){
    Serial.println("Wokwi: đang khởi tạo bộ nhớ mô phỏng còn trống.");
    storageOK=esp_littlefs_format("spiffs")==ESP_OK&&LittleFS.begin(false);
  }else
#endif
  storageOK=LittleFS.begin(false);
  if(!storageOK){Serial.println("LỖI BỘ NHỚ: thiết bị đang khóa. Chỉ nhập INIT_NEW_DEVICE nếu đây là thiết bị mới, bộ nhớ chưa có dữ liệu.");}
  if(storageOK&&LittleFS.exists("/state.json")){
    File f=LittleFS.open("/state.json","r");if(deserializeJson(state,f)){storageOK=false;Serial.println("LỖI BỘ NHỚ: dữ liệu trạng thái bị hỏng; đã khóa cơ cấu cấp.");}f.close();
  }else if(storageOK){defaults();persist();}
  if(storageOK){
    // Upgrade older Long state without resetting calibration, schedules or safety totals.
    JsonObject c=cfg();bool changed=false;
    const char* keys[]={"bowl_capacity_g","max_daily_feeds","max_feed_pulses","coarse_fine_threshold_g","anti_jam_max_retries","pulse_step_angle","pulse_step_ms"};
    const int values[]={150,6,15,10,3,90,600};
    for(int i=0;i<7;i++)if(c[keys[i]].isNull()){c[keys[i]]=values[i];changed=true;}
    if(c["lockdown"].isNull()){c["lockdown"]=false;changed=true;}
    if(state["feed_count"].isNull()){
      int count=0;for(JsonObject h:state["history"].as<JsonArray>())
        if(h["status"]!="REJECTED"&&h["status"]!="COMMAND_EXPIRED"&&dayKey(h["command"]["created_at"].as<long>())==state["day"].as<String>())count++;
      state["feed_count"]=count;changed=true;
    }
    if(changed)persist();
  }
  if(storageOK&&!state["active"].isNull()){
    JsonDocument old;old.set(state["active"]);state["active"]=nullptr;state["locked"]=true;
    result(old.as<JsonVariantConst>(),"INTERRUPTED",0,"RECONCILIATION_REQUIRED",false);
  }
  #if WOKWI_SIM
  simAuto=storageOK&&state["sim_auto"].as<bool>();
#endif
  busy=false;WiFi.mode(WIFI_STA);WiFi.setAutoReconnect(true);WiFi.begin("Wokwi-GUEST","",6);configTime(0,0,"pool.ntp.org","time.google.com");
  mqtt.setServer(MQTT_HOST,MQTT_PORT);mqtt.setCallback(callback);mqtt.setBufferSize(8192);mqtt.setSocketTimeout(1);mqtt.setKeepAlive(60);
  Serial.printf("Đang kết nối Wi-Fi Wokwi-GUEST và MQTT %s:%d.\n",MQTT_HOST,MQTT_PORT);
  Serial.println("PetFeeder đã sẵn sàng. Lệnh: status | sim manual | sim auto | sim jam on/off | sim empty. Cân HX711 không tự chỉnh về 0 khi khởi động.");
}
void loop(){
  while(Serial.available()){
    char c=Serial.read();if(c=='\n'||c=='\r'){
      if(!serialLine.length())continue; // Accept CR, LF and CRLF without repeating a command.
      Serial.println();serialLine.trim();
      if(serialLine=="INIT_NEW_DEVICE"&&!storageOK){
        if(LittleFS.format()&&LittleFS.begin(false)){storageOK=true;defaults();persist();
#if WOKWI_SIM
        simAuto=true;
#endif
        Serial.println("ĐÃ KHỞI TẠO: chỉ dùng cho thiết bị mới chưa có dữ liệu.");}
      }else if(storageOK)serialCommand(serialLine);serialLine="";
    }else if(c=='\b'||c==127){
      if(serialLine.length()){serialLine.remove(serialLine.length()-1);Serial.print("\b \b");}
    }else if(static_cast<uint8_t>(c)>=32&&serialLine.length()<4096){serialLine+=c;Serial.write(c);}
  }
  updatePanel();
  if(!storageOK){servo(false);delay(1);return;}
  unsigned long ms=millis();
  weightDropped=false;
  if(ms-distanceAt>=500){distanceAt=ms;
#if WOKWI_SIM
    if(simAuto)distanceCM=cf("tank_height_cm")*(1-state["sim_hopper_g"].as<float>()/500.0f);
    else
#endif
    {distanceCM=NAN;for(int attempt=0;attempt<3;attempt++){
      digitalWrite(TRIG_PIN,LOW);delayMicroseconds(2);digitalWrite(TRIG_PIN,HIGH);delayMicroseconds(10);digitalWrite(TRIG_PIN,LOW);
      unsigned long echo=pulseIn(ECHO_PIN,HIGH,25000);if(echo){distanceCM=echo/58.0f;break;}
    }}
  }
  if(ms-sampleAt>=100){
    sampleAt=ms;
    #if WOKWI_SIM
    if(simAuto){
      if(busy&&motorOpen&&!simJam&&ms-servoAt>=(finePulse?150:cf("pulse_step_ms")-50)){
        float remaining=state["active"]["target_portion_g"].as<float>()-(state["sim_bowl_g"].as<float>()-state["active"]["baseline"].as<float>());
        float gain=max(0.0f,min(finePulse?2.5f:5.0f,min(remaining,state["sim_hopper_g"].as<float>())));
        if(gain>0){state["sim_bowl_g"]=state["sim_bowl_g"].as<float>()+gain;state["sim_hopper_g"]=state["sim_hopper_g"].as<float>()-gain;servo(false);persist();Serial.printf("MÔ PHỎNG: lượng cân tăng %.1f g (số liệu giả lập).\n",gain);}
      }
      float w=state["sim_bowl_g"].as<float>();weightOK=isfinite(w);bowlMissing=false;weightG=w;
      trackWeight(ms);
    }else
#endif
    if(scale.is_ready()){
      float w=(scale.read()-state["offset"].as<long>())/state["factor"].as<float>();
      bowlMissing=isfinite(w)&&w<=-10;weightOK=isfinite(w)&&w>=-2&&w<=5000;weightG=max(0.0f,w);
      trackWeight(ms);
    }else if(ms-lastWeightAt>=1000)weightOK=false;
  }
  if(busy){
    if(state["locked"].as<bool>())finish("INTERRUPTED","RECONCILIATION_REQUIRED",false);
    else if(cfg()["lockdown"].as<bool>())finish("INTERRUPTED","SAFETY_LOCKOUT",false);
    else if(!weightOK)finish("SENSOR_ERROR",bowlMissing?"BOWL_MISSING":"MEASUREMENT_LOST",false);
    else{
      float actual=weightG-state["active"]["baseline"].as<float>(),target=state["active"]["target_portion_g"].as<float>();
      if(weightDropped)finish("INTERRUPTED","INTERRUPTED_PET_FEEDING",false);
      else if(actual>target+cf("tolerance_g"))finish("OVER_PORTION","OVER_PORTION");
      else if(ms-feedAt>=(unsigned long)(cf("feed_timeout_s")*1000)&&ms-stableAt<700)finish("SENSOR_ERROR","WEIGHT_UNSTABLE",false);
      else if(actual>0&&actual>=target-cf("tolerance_g")){servo(false);if(ms-stableAt>=700)finish("SUCCESS");}
      else if(!isfinite(distanceCM))finish("SENSOR_ERROR","ULTRASONIC_TIMEOUT");
      else if(distanceCM>=cf("empty_threshold_cm"))finish(actual>0?"PARTIAL":"FOOD_EMPTY","FOOD_EMPTY");
      else if(ms-feedAt>=(unsigned long)(cf("feed_timeout_s")*1000))finish(actual>0?"PARTIAL":"TIMEOUT","FEED_TIMEOUT");
      else if(!motorOpen&&!antiStep&&pulseCount>=cf("max_feed_pulses")&&ms-servoAt>=600&&ms-stableAt>=700)finish(actual>0?"PARTIAL":"TIMEOUT","MAX_PULSES_REACHED");
      else if(antiStep){
        if(ms-antiAt>=150){antiAt=ms;antiStep++;antiServo(antiStep%2?45:135);
          if(antiStep>=7){antiStep=0;antiServo(90);servo(false);servoAt=ms;pulseBaseline=weightG;
            if(jamRetries>=cf("anti_jam_max_retries"))finish("JAM_ERROR","JAM_ERROR");
            else if(pulseCount>=cf("max_feed_pulses"))finish(actual>0?"PARTIAL":"TIMEOUT","MAX_PULSES_REACHED");
            else{finePulse=target-actual<=cf("coarse_fine_threshold_g");pulseCount++;servo(true);}
          }
        }
      }else if(motorOpen){
        if(ms-servoAt>=(finePulse?200:cf("pulse_step_ms"))){servo(false);servoAt=ms;}
      }else if(ms-servoAt>=600&&ms-stableAt>=700){
          if(weightG-pulseBaseline<1){jamRetries++;antiStep=1;antiAt=ms;antiServo(45);servoAngle(120);toneNotice(200);Serial.printf("CHỐNG KẸT: đang thử thông đường cấp lần %d/3.\n",jamRetries);}
          else{jamRetries=0;finePulse=target-actual<=cf("coarse_fine_threshold_g");pulseCount++;servo(true);}
          pulseBaseline=weightG;
        servoAt=ms;
      }
    }
  }
  if(WiFi.status()==WL_CONNECTED){
    if(!mqtt.connected()&&!busy&&ms-connectAt>=3000){connectAt=ms;
      if(mqtt.connect((String("esp-")+DEVICE_ID).c_str(),MQTT_USER,MQTT_PASS)){
        Serial.printf("Đã kết nối MQTT tới %s:%d.\n",MQTT_HOST,MQTT_PORT);
        mqtt.subscribe((root+"/command").c_str(),1);mqtt.subscribe((root+"/sync").c_str(),1);mqtt.subscribe((root+"/ack").c_str(),1);heartbeat();
      }
    }
    if(mqtt.connected()){
      mqtt.loop();
      if(ms-beatAt>=5000){beatAt=ms;heartbeat();}
      if(ms-publishAt>=1000&&state["events"].size()){
        publishAt=ms;String e;serializeJson(state["events"][0],e);mqtt.publish((root+"/events").c_str(),e.c_str(),false);
      }
    }
  }
  if(ms-scanAt>=1000){
    scanAt=ms;scanSchedules();
    if(!busy&&weightOK&&ms-stableAt>=700){
      if(idleWeightKnown&&fabs(weightG-idleWeight)>5){
        JsonDocument ref;ref["delta_g"]=weightG-idleWeight;ref["current_bowl_weight_g"]=weightG;
        const bool refill=weightG>idleWeight;
        emit(refill?"MANUAL_REFILL":"WEIGHT_DECREASED",ref.as<JsonVariantConst>(),JsonVariantConst(),refill?"OWNER_REFILL":"UNKNOWN_CAUSE");
        idleWeight=weightG;
      }
      if(!idleWeightKnown){idleWeight=weightG;idleWeightKnown=true;}
    }
    static bool invalidReported=false;
    if(!validTime()&&!invalidReported){invalidReported=true;event("TIME_INVALID");}
    if(validTime()){
      long now=nowSec();
      if(weightOK&&weightG>1&&!state["food_since"].as<long>()){state["food_since"]=now;state["stale_alert"]=false;persist();}
      if(weightOK&&weightG<=1&&state["food_since"].as<long>()){state["food_since"]=0;state["stale_alert"]=false;persist();}
      if(weightOK&&state["food_since"].as<long>()&&!state["stale_alert"].as<bool>()&&now-state["food_since"].as<long>()>=cf("food_stale_s")){
        state["stale_alert"]=true;event("FOOD_STALE");}
      JsonArray obs=state["observations"].as<JsonArray>();
      for(int i=(int)obs.size()-1;i>=0;i--)if(now-obs[i]["at"].as<long>()>=cf("observation_s")){
        JsonDocument ref;ref["command_id"]=obs[i]["command_id"];
        const char* status=!weightOK?"UNKNOWN":weightG<obs[i]["baseline"].as<float>()-cf("tolerance_g")?"WEIGHT_DECREASED":"FOOD_LEFT";
        emit(status,ref.as<JsonVariantConst>(),JsonVariantConst(),!strcmp(status,"WEIGHT_DECREASED")?"UNKNOWN_CAUSE":nullptr);obs.remove(i);persist();
      }
    }
  }
  static bool wasDown=false;static unsigned long pressedAt=0;
  bool down=digitalRead(BUTTON_PIN)==LOW;
  if(down&&!wasDown&&ms-pressedAt>100){pressedAt=ms;if(!validTime()){event("TIME_INVALID");wasDown=down;return;}JsonDocument c;c["command_id"]="btn:"+id();c["source"]="BUTTON";
    c["target_portion_g"]=20;c["created_at"]=nowSec();c["expires_at"]=nowSec()+(int)cf("command_ttl_s");c["override"]=false;receive(c.as<JsonVariantConst>());}
  wasDown=down;delay(1);
}
