// Long: MQTT, persistent state/schedules, retry protection and recovery.
// Actuator/sensor driver is a bounded demo to integrate with Danh's final firmware.
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <LittleFS.h>
#include <HX711.h>
#include <time.h>
#if __has_include("secrets.h")
#include "secrets.h"
#else
#include "secrets.example.h"
#endif

constexpr int SERVO_PIN=18, BUTTON_PIN=27, DT_PIN=16, SCK_PIN=4;
constexpr int TRIG_PIN=23, ECHO_PIN=19;
constexpr size_t MAX_EVENTS=96, MAX_HISTORY=32;
WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);
HX711 scale;
JsonDocument state;
bool storageOK=false,weightOK=false,busy=false,motorOpen=false;
float weightG=0,lastSample=0;
unsigned long sampleAt=0,stableAt=0,beatAt=0,publishAt=0,connectAt=0,scanAt=0;
unsigned long feedAt=0,servoAt=0;
unsigned long scanSavedAt=0;
String serialLine;
String bootId;
String root=String("petfeeder/")+DEVICE_ID;
bool validTime(){return time(nullptr)>1700000000;}
long nowSec(){return (long)time(nullptr);}
void servo(bool open){motorOpen=open;ledcWrite(0,(uint32_t)((open?1500:500)*65535UL/20000));}
bool persist(){
  if(!storageOK)return false;
  File f=LittleFS.open("/state.tmp","w");
  if(!f)return storageOK=false;
  const size_t expected=measureJson(state),written=serializeJson(state,f);
  f.flush();f.close();
  if(written!=expected || !LittleFS.rename("/state.tmp","/state.json")){
    servo(false);storageOK=false;Serial.println("STORAGE_ERROR: actuator locked");return false;
  }
  return true;
}
JsonObject cfg(){return state["config"].as<JsonObject>();}
float cf(const char* key){return cfg()[key].as<float>();}
String id(){char b[17];snprintf(b,sizeof(b),"%08lx%08lx",(unsigned long)esp_random(),(unsigned long)esp_random());return String(b);}
void defaults(){
  JsonObject c=state["config"].to<JsonObject>();
  c["max_portion_g"]=100;c["daily_limit_g"]=200;c["min_interval_s"]=180;
  c["observation_s"]=60;c["food_stale_s"]=3600;c["command_ttl_s"]=60;
  c["feed_timeout_s"]=30;c["tolerance_g"]=2;c["timezone_offset_min"]=420;
  c["require_pet"]=false;c["food_confirmed"]=false;c["food_label"]="";
  state["events"].to<JsonArray>();state["history"].to<JsonArray>();state["schedules"].to<JsonArray>();
  state["runs"].to<JsonArray>();state["observations"].to<JsonArray>();
  state["seq"]=0;state["last_end"]=0;state["last_scan"]=0;state["locked"]=false;
  state["used_g"]=0;state["day"]="";state["food_since"]=0;
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
bool emit(const char* status,JsonVariantConst c=JsonVariantConst(),JsonVariantConst actual=JsonVariantConst(),const char* error=nullptr){
  if(state["events"].size()>=MAX_EVENTS){servo(false);state["locked"]=true;persist();return false;}
  JsonObject e=state["events"].as<JsonArray>().add<JsonObject>();
  e["event_id"]=String(DEVICE_ID)+":"+id();e["seq"]=state["seq"].as<unsigned long>()+1;state["seq"]=e["seq"];
  e["occurred_at"]=validTime()?nowSec():0;e["status"]=status;
  if(!c.isNull() && c["command_id"].is<const char*>()){
    e["command_id"]=c["command_id"];
    if(c["source"].is<const char*>())e["source"]=c["source"];
    if(numeric(c["target_portion_g"],0,500))e["target_portion_g"]=c["target_portion_g"];
    e["actual_weight_g"].set(actual);
  }
  if(error)e["error_code"]=error;
  String line;serializeJson(e,line);Serial.println(line);
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
  servo(false);JsonDocument copy;copy.set(state["active"]);auto a=copy.as<JsonObject>();
  float actual=max(0.0f,weightG-a["baseline"].as<float>());
  if(known)state["used_g"]=max(0.0f,state["used_g"].as<float>()-a["target_portion_g"].as<float>()+actual);
  else state["locked"]=true;
  state["active"]=nullptr;busy=false;state["last_end"]=validTime()?nowSec():state["last_end"].as<long>();
  if(known&&actual>0&&state["observations"].size()<8){auto o=state["observations"].as<JsonArray>().add<JsonObject>();
    o["command_id"]=a["command_id"];o["at"]=nowSec();o["baseline"]=weightG;}
  result(a,status,actual,error,known);
}
bool commandValid(JsonVariantConst c){
  return c.is<JsonObjectConst>()&&ident(c["command_id"])&&c["source"].is<const char*>()&&
    (c["source"]=="APP"||c["source"]=="SCHEDULE"||c["source"]=="BUTTON")&&
    numeric(c["target_portion_g"],1,cf("max_portion_g"))&&numeric(c["created_at"],1700000000,4102444800.0,true)&&
    numeric(c["expires_at"],1700000000,4102444800.0,true)&&c["override"].is<bool>()&&!c["override"].as<bool>()&&
    c["expires_at"].as<long>()>c["created_at"].as<long>()&&c["expires_at"].as<long>()-c["created_at"].as<long>()<=300;
}
void receive(JsonVariantConst c){
  if(!commandValid(c)){if(ident(c["command_id"]))reject(c,"INVALID_FIELD");else event("REJECTED","INVALID_FIELD");return;}
  if(busy&&state["active"]["command_id"]==c["command_id"]){event("BLOCKED_DUPLICATE");return;}
  for(JsonObject old:state["history"].as<JsonArray>())if(old["command"]["command_id"]==c["command_id"]){
    String before,after;serializeJson(old["command"],before);serializeJson(c,after);
    // Compare semantic fields, independent of JSON field order.
    for(const char* k:{"source","target_portion_g","created_at","expires_at","override"})if(old["command"][k]!=c[k]){event("REJECTED","COMMAND_ID_CONFLICT");return;}
    event("BLOCKED_DUPLICATE");
    JsonDocument val;val.set(old["actual_weight_g"]);emit(old["status"].as<const char*>(),c,val.as<JsonVariantConst>(),old["error_code"].as<const char*>());return;
  }
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
  if(cfg()["require_pet"].as<bool>()){reject(c,"UNKNOWN_PET");return;}
  if(!cfg()["food_confirmed"].as<bool>()){reject(c,"UNVERIFIED");return;}
  if(!state["calibrated"].as<bool>()||!weightOK||millis()-stableAt<500){reject(c,"SENSOR_ERROR");return;}
  if(now-state["last_end"].as<long>()<cf("min_interval_s")){reject(c,"COOLDOWN");return;}
  String day=dayKey(now);
  if(state["day"].as<String>()!=day){state["day"]=day;state["used_g"]=0;}
  float target=c["target_portion_g"].as<float>();
  if(state["used_g"].as<float>()+target>cf("daily_limit_g")){reject(c,"DAILY_LIMIT");return;}
  digitalWrite(TRIG_PIN,LOW);delayMicroseconds(2);digitalWrite(TRIG_PIN,HIGH);delayMicroseconds(10);digitalWrite(TRIG_PIN,LOW);
  unsigned long echo=pulseIn(ECHO_PIN,HIGH,25000); // bounded 25ms, never a long feeding loop
  if(!echo){reject(c,"SENSOR_ERROR");return;}
  if(echo/58.0>30){reject(c,"FOOD_EMPTY");return;}
  state["active"].set(c);state["active"]["baseline"]=weightG;state["active"]["started_at"]=now;
  state["used_g"]=state["used_g"].as<float>()+target;
  remember(c,"DISPENSING",0);
  if(!storageOK)return;busy=true;feedAt=millis();servoAt=millis();servo(true);
  JsonDocument zero;zero.set(0);emit("ACCEPTED",c,zero.as<JsonVariantConst>());emit("DISPENSING",c,zero.as<JsonVariantConst>());
}
bool configValid(JsonVariantConst c){
  if(!c.is<JsonObjectConst>())return false;
  struct Bound{const char* key;float lo,hi;};
  Bound bs[]={{"max_portion_g",1,500},{"daily_limit_g",1,2000},{"min_interval_s",1,86400},
    {"observation_s",5,86400},{"food_stale_s",5,604800},{"command_ttl_s",5,300},
    {"feed_timeout_s",5,120},{"tolerance_g",0.1,10},{"timezone_offset_min",-720,840}};
  for(auto b:bs)if(!numeric(c[b.key],b.lo,b.hi,strcmp(b.key,"tolerance_g")!=0))return false;
  return c["require_pet"].is<bool>()&&c["food_confirmed"].is<bool>()&&c["food_label"].is<const char*>()&&
    strlen(c["food_label"].as<const char*>())<=80&&(!c["food_confirmed"].as<bool>()||strlen(c["food_label"].as<const char*>())>0)&&
    c["max_portion_g"].as<float>()<=c["daily_limit_g"].as<float>()&&c["tolerance_g"].as<float>()<c["max_portion_g"].as<float>();
}
bool scheduleValid(JsonVariantConst items,float maxPortion){
  if(!items.is<JsonArrayConst>()||items.size()>8)return false;
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
    if(!configValid(d["config"])||!scheduleValid(d["schedules"],d["config"]["max_portion_g"].as<float>())){event("REJECTED","INVALID_CONFIG_OR_SCHEDULE");return;}
    if(busy){event("REJECTED","CONFIG_BUSY");return;}
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
  JsonDocument h;h["occurred_at"]=validTime()?nowSec():0;h["busy"]=busy;h["time_valid"]=validTime();
  if(weightOK)h["weight_g"]=weightG;else h["weight_g"]=nullptr;
  h["locked"]=state["locked"].as<bool>()||!storageOK;h["food_since"]=state["food_since"];
  h["outbox"]=state["events"].size();h["mode"]="ESP32";h["boot_id"]=bootId;h["config_version"]=state["config_version"];
  String b;serializeJson(h,b);mqtt.publish((root+"/telemetry").c_str(),b.c_str(),false);
}
void serialCommand(String line){
  line.trim();
  if(line=="status"){heartbeat();Serial.printf("weight=%.1fg calibrated=%d time_valid=%d busy=%d\n",weightG,state["calibrated"].as<bool>(),validTime(),busy);}
  else if(line=="tare EMPTY"&&!busy&&weightOK){state["offset"]=scale.read();state["calibrated"]=true;persist();Serial.println("CALIBRATED: empty bowl offset saved");}
  else if(line.startsWith("factor ")&&!busy){float factor=line.substring(7).toFloat();if(isfinite(factor)&&factor>0){state["factor"]=factor;state["calibrated"]=false;persist();Serial.println("Now run tare EMPTY with empty bowl");}}
  else if(line=="reconcile CHECKED"&&!busy&&weightOK&&validTime()){
    state["locked"]=false;state["last_end"]=nowSec();persist();event("RECONCILED","DAILY_RESERVATION_RETAINED");}
  else if(line=="food CONFIRMED"&&!busy){cfg()["food_confirmed"]=true;cfg()["food_label"]="Chu xac nhan qua Serial";persist();event("OWNER_FOOD_CONFIRMED");}
  else if(line.startsWith("{")){JsonDocument d;if(!deserializeJson(d,line))receive(d.as<JsonVariantConst>());else event("REJECTED","INVALID_JSON");}
  else Serial.println("Commands: status | food CONFIRMED | tare EMPTY | factor N | reconcile CHECKED | JSON command");
}
void setup(){
  Serial.begin(115200);bootId=id();ledcSetup(0,50,16);ledcAttachPin(SERVO_PIN,0);servo(false);
  pinMode(BUTTON_PIN,INPUT_PULLUP);pinMode(TRIG_PIN,OUTPUT);pinMode(ECHO_PIN,INPUT);scale.begin(DT_PIN,SCK_PIN);
  // Do not format on a mount error: formatting could erase anti-repeat state after a transient failure.
  storageOK=LittleFS.begin(false);
  if(!storageOK){Serial.println("STORAGE_NOT_INITIALIZED: send INIT_NEW_DEVICE to format ONLY a new empty device");}
  if(storageOK&&LittleFS.exists("/state.json")){
    File f=LittleFS.open("/state.json","r");if(deserializeJson(state,f)){storageOK=false;Serial.println("STORAGE_CORRUPT: locked");}f.close();
  }else if(storageOK){defaults();persist();}
  if(storageOK&&!state["active"].isNull()){
    JsonDocument old;old.set(state["active"]);state["active"]=nullptr;state["locked"]=true;
    result(old.as<JsonVariantConst>(),"INTERRUPTED",0,"RECONCILIATION_REQUIRED",false);
  }
  busy=false;WiFi.mode(WIFI_STA);WiFi.begin("Wokwi-GUEST","",6);configTime(0,0,"pool.ntp.org","time.google.com");
  mqtt.setServer(MQTT_HOST,MQTT_PORT);mqtt.setCallback(callback);mqtt.setBufferSize(8192);mqtt.setSocketTimeout(1);
  Serial.println("PetFeeder Long ready. HX711 never tares on boot. Type status for readings.");
}
void loop(){
  while(Serial.available()){
    char c=Serial.read();if(c=='\n'){
      if(serialLine=="INIT_NEW_DEVICE"&&!storageOK){
        if(LittleFS.format()&&LittleFS.begin(false)){storageOK=true;defaults();persist();Serial.println("INITIALIZED; new device only");}
      }else if(storageOK)serialCommand(serialLine);serialLine="";
    }else if(c!='\r'&&serialLine.length()<4096)serialLine+=c;
  }
  if(!storageOK){servo(false);delay(1);return;}
  unsigned long ms=millis();
  if(ms-sampleAt>=100){
    sampleAt=ms;
    if(scale.is_ready()){
      float w=(scale.read()-state["offset"].as<long>())/state["factor"].as<float>();
      weightOK=isfinite(w)&&w>=-2&&w<=5000;weightG=max(0.0f,w);
      if(fabs(weightG-lastSample)>cf("tolerance_g"))stableAt=ms;lastSample=weightG;
    }else weightOK=false;
  }
  if(busy){
    if(state["locked"].as<bool>())finish("INTERRUPTED","RECONCILIATION_REQUIRED",false);
    else if(!weightOK)finish("SENSOR_ERROR","MEASUREMENT_LOST",false);
    else{
      float actual=weightG-state["active"]["baseline"].as<float>(),target=state["active"]["target_portion_g"].as<float>();
      if(actual>target+cf("tolerance_g"))finish("OVER_PORTION","OVER_PORTION");
      else if(ms-feedAt>=(unsigned long)(cf("feed_timeout_s")*1000)&&ms-stableAt<700)finish("SENSOR_ERROR","WEIGHT_UNSTABLE",false);
      else if(actual>=target-cf("tolerance_g")){servo(false);if(ms-stableAt>=700)finish("SUCCESS");}
      else if(ms-feedAt>=(unsigned long)(cf("feed_timeout_s")*1000))finish(actual>0?"PARTIAL":"TIMEOUT","FEED_TIMEOUT");
      else if(ms-servoAt>=500){servoAt=ms;servo(!motorOpen);}
    }
  }
  if(WiFi.status()==WL_CONNECTED){
    if(!mqtt.connected()&&!busy&&ms-connectAt>=3000){connectAt=ms;
      if(mqtt.connect((String("esp-")+DEVICE_ID).c_str(),MQTT_USER,MQTT_PASS)){
        mqtt.subscribe((root+"/command").c_str(),1);mqtt.subscribe((root+"/sync").c_str(),1);mqtt.subscribe((root+"/ack").c_str(),1);heartbeat();
      }
    }
    if(mqtt.connected()){
      mqtt.loop();
      if(ms-beatAt>=5000){beatAt=ms;heartbeat();}
      if(ms-publishAt>=1000&&state["events"].size()){
        publishAt=ms;String e;serializeJson(state["events"][0],e);mqtt.publish((root+"/event").c_str(),e.c_str(),false);
      }
    }
  }
  if(ms-scanAt>=1000){
    scanAt=ms;scanSchedules();
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
  if(down&&!wasDown&&ms-pressedAt>100){pressedAt=ms;JsonDocument c;c["command_id"]="btn:"+id();c["source"]="BUTTON";
    c["target_portion_g"]=20;c["created_at"]=nowSec();c["expires_at"]=nowSec()+(int)cf("command_ttl_s");c["override"]=false;receive(c.as<JsonVariantConst>());}
  wasDown=down;delay(1);
}
