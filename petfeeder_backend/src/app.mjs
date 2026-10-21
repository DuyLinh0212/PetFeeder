import mqtt from 'mqtt';
import {createHash,randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {FeedingService} from './services/feedingService.mjs';
import {Storage} from './storage/database.mjs';
import {migrateLegacy} from './storage/legacyMigration.mjs';
import {createApiRouter} from './routes/index.mjs';
import {createVisionRouter} from './routes/vision.mjs';

const validIdentifier=value=>typeof value==='string'&&/^[A-Za-z0-9_.:-]{1,96}$/.test(value);
function epochSeconds(value,fallback){
  if(typeof value==='number'&&Number.isFinite(value)){
    const seconds=value>4102444800?Math.floor(value/1000):Math.floor(value);
    if(seconds>=0&&seconds<=4102444800)return seconds;
  }
  if(typeof value==='string'&&value.trim()){
    const numeric=Number(value);
    if(Number.isFinite(numeric))return epochSeconds(numeric,fallback);
    const parsed=Date.parse(value);
    if(Number.isFinite(parsed))return epochSeconds(parsed/1000,fallback);
  }
  return fallback;
}
function legacyStatus(value){
  const raw=String(value||'LEGACY_EVENT').trim().toUpperCase();
  const known=new Map([['HOAN TAT','SUCCESS'],['HOAN TAT!','SUCCESS'],['CAP THIEU','PARTIAL'],['CAP THIEU!','PARTIAL']]);
  if(known.has(raw))return known.get(raw);
  const normalized=raw.replace(/[^A-Z0-9_.:-]+/g,'_').replace(/^_+|_+$/g,'').slice(0,96);
  return validIdentifier(normalized)?normalized:'LEGACY_EVENT';
}
function normalizeHeartbeat(payload,clock){
  const deviceId=typeof payload.device_id==='string'?payload.device_id:'petfeeder_01';
  const weight=typeof payload.weight_g==='number'?payload.weight_g:
    typeof payload.bowl_weight_g==='number'?payload.bowl_weight_g:null;
  return {
    device_id:deviceId,
    status:typeof payload.status==='string'?payload.status:'SAN SANG',
    occurred_at:epochSeconds(payload.occurred_at??payload.timestamp,clock()),
    busy:typeof payload.busy==='boolean'?payload.busy:/DANG\s*(CAP|CHO AN)/i.test(String(payload.status||'')),
    weight_g:weight,
    ip:typeof payload.ip==='string'?payload.ip:'',
    rssi:Number.isInteger(payload.rssi)?payload.rssi:0,
    locked:payload.locked===true,
    time_valid:payload.time_valid===true,
    sensor_mode:typeof payload.sensor_mode==='string'?payload.sensor_mode:'UNKNOWN',
    pet_detected_yolo:payload.pet_detected_yolo===true,
    ...(typeof payload.pet_id==='string'?{pet_id:payload.pet_id}:{}),
    boot_id:typeof payload.boot_id==='string'?payload.boot_id:`legacy:${deviceId}`,
    config_version:typeof payload.config_version==='string'?payload.config_version:'',
  };
}
function normalizeEvent(payload,body,db,clock){
  const receivedAt=clock();
  let occurredAt=epochSeconds(payload.occurred_at??payload.timestamp,receivedAt);
  // Keep events from an unset device clock out of 1970. Heartbeats retain
  // occurred_at=0 so FeedingService can detect the skew and send a time sync.
  if(occurredAt<1700000000)occurredAt=receivedAt;
  const hasModernId=validIdentifier(payload.event_id);
  const eventId=hasModernId?payload.event_id:`legacy:${createHash('sha256').update(body).digest('hex').slice(0,32)}`;
  const commandId=validIdentifier(payload.command_id)?payload.command_id:undefined;
  const command=commandId?db.get('commands',commandId):null;
  const seq=Number.isInteger(payload.seq)&&payload.seq>0?payload.seq:Math.max(1,(command?.last_seq||0)+1);
  const status=legacyStatus(payload.status??payload.event);
  const event={event_id:eventId,seq,occurred_at:occurredAt,status};
  if(commandId)event.command_id=commandId;
  if(['APP','BUTTON','SCHEDULE'].includes(payload.source))event.source=payload.source;
  if(typeof payload.target_portion_g==='number')event.target_portion_g=payload.target_portion_g;
  if(typeof payload.actual_weight_g==='number'||payload.actual_weight_g===null)event.actual_weight_g=payload.actual_weight_g;
  for(const key of ['pet_id','recognition_id','recognition_source'])if(typeof payload[key]==='string')event[key]=payload[key].slice(0,96);
  if(typeof payload.confidence==='number'&&Number.isFinite(payload.confidence))event.confidence=payload.confidence;
  if(typeof payload.error_code==='string')event.error_code=payload.error_code.slice(0,96);
  return {event,ackId:hasModernId?payload.event_id:null};
}

// Compose storage, command handling, MQTT and the REST API.
export function createBackend({dataDir,legacyFile,brokerUrl,prefix='duylinh0212/petfeeder/v1',clock=()=>Math.floor(Date.now()/1000),transport:injected}={}){
  const db=new Storage(resolve(dataDir||process.env.DATA_DIR||fileURLToPath(new URL('../data/main/',import.meta.url)),'backend.sqlite'));
  try {migrateLegacy(db,legacyFile??(dataDir||process.env.DATA_DIR?null:fileURLToPath(new URL('../data/database.json',import.meta.url))));}
  catch(error){db.close();throw error;}
  let service,client;
  const transport=injected||{mode:'MQTT',send(kind,body){
    if(!client?.connected)return false;
    client.publish(`${prefix}/${kind}`,JSON.stringify(body),{qos:1,retain:false});return true;
  }};
  service=new FeedingService(db,transport,clock);
  function onMessage(topic,body,packet={}){
    if(packet.retain)return; // Current heartbeat and outbox events must be live.
    const payload=JSON.parse(body.toString());
    if(topic===`${prefix}/telemetry`)service.heartbeat(normalizeHeartbeat(payload,clock));
    else if(topic===`${prefix}/events`){
      const {event,ackId}=normalizeEvent(payload,body,db,clock);
      service.event(event); // SQLite commits before acknowledging the event.
      if(ackId)client?.publish(`${prefix}/ack`,JSON.stringify({event_id:ackId}),{qos:1,retain:false});
    }
  }
  if(!injected){
    client=mqtt.connect(brokerUrl||process.env.MQTT_BROKER_URL||'mqtt://broker.emqx.io:1883',{
      clientId:`petfeeder-main-${randomUUID()}`,clean:true,reconnectPeriod:3000,
      username:process.env.MQTT_USERNAME,password:process.env.MQTT_PASSWORD,
    });
    client.on('connect',()=>client.subscribe([`${prefix}/events`,`${prefix}/telemetry`],{qos:1},()=>service.sync()));
    client.on('message',(topic,body,packet)=>{try{onMessage(topic,body,packet);}catch(e){
      let payload={};try{payload=JSON.parse(body.toString());}catch{}
      const time=payload.occurred_at??payload.timestamp;
      const detail=time===undefined?'thiếu thời gian thiết bị':`thời gian=${JSON.stringify(time)} (${typeof time})`;
      console.error(`[MQTT] Không xử lý được gói từ ${topic}: ${e.message}; ${detail}`);
    }});
    client.on('error',e=>console.error('[MQTT] Lỗi kết nối broker:',e.message));
  }
  function tick(){
    for(const c of db.all('commands'))if(c.status==='QUEUED'){
      if(clock()>=c.expires_at)db.put('commands',c.command_id,{...c,status:'DELIVERY_UNKNOWN',error_code:'AWAITING_DEVICE_RESULT'});
      else transport.send('command',c);
    }
  }
  const timer=setInterval(tick,1000);timer.unref();
  const connected=()=>injected?true:!!client?.connected;
  const {router,device}=createApiRouter({db,service,clock,connected});
  router.use('/vision',createVisionRouter({service,clock}));
  return {router,service,db,device,onMessage,tick,connected,close(){clearInterval(timer);client?.end(true);db.close();}};
}
