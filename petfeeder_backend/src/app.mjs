import mqtt from 'mqtt';
import {createHash,randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {FeedingService} from './services/feedingService.mjs';
import {Storage} from './storage/database.mjs';
import {PostgresStorage} from './storage/postgres.mjs';
import {migrateLegacy} from './storage/legacyMigration.mjs';
import {createApiRouter} from './routes/index.mjs';

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
  const distance=typeof payload.distance_cm==='number'&&Number.isFinite(payload.distance_cm)&&payload.distance_cm>=0&&payload.distance_cm<=500
    ?payload.distance_cm:null;
  const foodLevel=typeof payload.food_level_percent==='number'&&Number.isFinite(payload.food_level_percent)&&payload.food_level_percent>=0&&payload.food_level_percent<=100
    ?Math.round(payload.food_level_percent):null;
  return {
    device_id:deviceId,
    status:typeof payload.status==='string'?payload.status:'SAN SANG',
    occurred_at:epochSeconds(payload.occurred_at??payload.timestamp,clock()),
    busy:typeof payload.busy==='boolean'?payload.busy:/DANG\s*(CAP|CHO AN)/i.test(String(payload.status||'')),
    weight_g:weight,
    distance_cm:distance,
    food_level_percent:foodLevel,
    ip:typeof payload.ip==='string'?payload.ip:'',
    rssi:Number.isInteger(payload.rssi)?payload.rssi:0,
    locked:payload.locked===true,
    time_valid:payload.time_valid===true,
    sensor_mode:typeof payload.sensor_mode==='string'?payload.sensor_mode:'UNKNOWN',
    boot_id:typeof payload.boot_id==='string'?payload.boot_id:`legacy:${deviceId}`,
    outbox:Number.isInteger(payload.outbox)&&payload.outbox>=0?payload.outbox:0,
    outbox_overflow_count:Number.isInteger(payload.outbox_overflow_count)&&payload.outbox_overflow_count>=0?payload.outbox_overflow_count:0,
    config_version:typeof payload.config_version==='string'?payload.config_version:'',
  };
}
async function normalizeEvent(payload,body,db,clock){
  const receivedAt=clock();
  let occurredAt=epochSeconds(payload.occurred_at??payload.timestamp,receivedAt);
  // Keep events from an unset device clock out of 1970. Heartbeats retain
  // occurred_at=0 so FeedingService can detect the skew and send a time sync.
  if(occurredAt<1700000000)occurredAt=receivedAt;
  const hasModernId=validIdentifier(payload.event_id);
  const eventId=hasModernId?payload.event_id:`legacy:${createHash('sha256').update(body).digest('hex').slice(0,32)}`;
  const commandId=validIdentifier(payload.command_id)?payload.command_id:undefined;
  const command=commandId?await db.get('commands',commandId):null;
  const seq=Number.isInteger(payload.seq)&&payload.seq>0?payload.seq:Math.max(1,(command?.last_seq||0)+1);
  const status=legacyStatus(payload.status??payload.event);
  const event={v:Number.isInteger(payload.v)?payload.v:1,device_id:validIdentifier(payload.device_id)?payload.device_id:'petfeeder_01',
    boot_id:validIdentifier(payload.boot_id)?payload.boot_id:`legacy:${eventId}`,event_id:eventId,seq,occurred_at:occurredAt,status};
  if(commandId)event.command_id=commandId;
  if(['APP','BUTTON','SCHEDULE'].includes(payload.source))event.source=payload.source;
  if(typeof payload.target_portion_g==='number')event.target_portion_g=payload.target_portion_g;
  if(typeof payload.actual_weight_g==='number'||payload.actual_weight_g===null)event.actual_weight_g=payload.actual_weight_g;
  if(typeof payload.error_code==='string')event.error_code=payload.error_code.slice(0,96);
  if(Number.isInteger(payload.overflow_count)&&payload.overflow_count>=0)event.overflow_count=payload.overflow_count;
  return {event,ackId:hasModernId?payload.event_id:null};
}

// Compose storage, command handling, MQTT and the REST API.
export async function createBackend({dataDir,legacyFile,brokerUrl,databaseUrl,storage,prefix='duylinh0212/petfeeder/v1',clock=()=>Math.floor(Date.now()/1000),transport:injected}={}){
  const db=storage||(dataDir||process.env.NODE_ENV==='test'
    ?new Storage(resolve(dataDir||fileURLToPath(new URL('../data/test/',import.meta.url)),'backend.sqlite'))
    :new PostgresStorage(databaseUrl||process.env.DATABASE_URL));
  try {
    await db.initialize?.();
    await migrateLegacy(db,legacyFile??(dataDir?null:fileURLToPath(new URL('../data/database.json',import.meta.url))));
  } catch(error) { await db.close?.(); throw error; }
  let service,client;
  let realtimePublisher=()=>{};
  const transport=injected||{mode:'MQTT',send(kind,body){
    if(!client?.connected)return false;
    return new Promise(resolve=>client.publish(`${prefix}/${kind}`,JSON.stringify(body),{qos:1,retain:false},error=>resolve(!error)));
  }};
  service=new FeedingService(db,transport,clock);
  async function onMessage(topic,body,packet={}){
    if(packet.retain)return; // Current heartbeat and outbox events must be live.
    const payload=JSON.parse(body.toString());
    if(topic===`${prefix}/telemetry`){
      await service.heartbeat(normalizeHeartbeat(payload,clock));
      realtimePublisher({type:'device_state',data:await device()});
    }
    else if(topic===`${prefix}/events`){
      const {event,ackId}=await normalizeEvent(payload,body,db,clock);
      await service.event(event); // Commit to PostgreSQL before acknowledging the event.
      if(ackId)client?.publish(`${prefix}/ack`,JSON.stringify({event_id:ackId}),{qos:1,retain:false});
      realtimePublisher({type:'feeding_event',data:event});
      realtimePublisher({type:'device_state',data:await device()});
    }
  }
  let messageQueue=Promise.resolve();
  function reportMessageError(topic,body,error){
    let payload={};try{payload=JSON.parse(body.toString());}catch{}
    const time=payload.occurred_at??payload.timestamp;
    const detail=time===undefined?'thiếu thời gian thiết bị':`thời gian=${JSON.stringify(time)} (${typeof time})`;
    console.error(`[MQTT] Không xử lý được gói từ ${topic}: ${error.message}; ${detail}`);
  }
  if(!injected){
    client=mqtt.connect(brokerUrl||process.env.MQTT_BROKER_URL||'mqtt://broker.emqx.io:1883',{
      clientId:`petfeeder-main-${randomUUID()}`,clean:true,reconnectPeriod:3000,
      username:process.env.MQTT_USERNAME,password:process.env.MQTT_PASSWORD,
    });
    client.on('connect',()=>client.subscribe([`${prefix}/events`,`${prefix}/telemetry`],{qos:1},error=>{
      if(error){console.error('[MQTT] Không đăng ký được topic sự kiện:',error.message);return;}
      void service.sync().then(replayPendingCommands).catch(e=>console.error('[MQTT] Không đồng bộ được thiết bị:',e.message));
    }));
    client.on('message',(topic,body,packet)=>{
      messageQueue=messageQueue.then(()=>onMessage(topic,body,packet)).catch(error=>reportMessageError(topic,body,error));
    });
    client.on('error',e=>console.error('[MQTT] Lỗi kết nối broker:',e.message));
  }
  async function replayPendingCommands(){
    if(!client?.connected)return;
    const pending=db.pendingCommands?await db.pendingCommands():(await db.all('commands')).filter(row=>row.status==='QUEUED');
    for(const command of pending){
      const sent=await transport.send('command',Object.fromEntries(
        ['command_id','source','target_portion_g','created_at','expires_at']
          .filter(key=>command[key]!==undefined).map(key=>[key,command[key]]),
      ));
      if(sent===false)break;
      await db.markCommandPublished?.(command.command_id);
    }
  }
  async function tick(){
    const now=clock();
    for(const c of await db.all('commands'))if(c.status==='QUEUED'){
      if(now>=c.expires_at)await db.put('commands',c.command_id,{...c,status:'DELIVERY_UNKNOWN',error_code:'AWAITING_DEVICE_RESULT'});
    }
  }
  const timer=setInterval(()=>void tick().catch(e=>console.error('[DB] Không cập nhật được trạng thái lệnh:',e.message)),1000);timer.unref();
  const connected=()=>injected?true:!!client?.connected;
  const {router,device}=createApiRouter({db,service,clock,connected,publishRealtime:message=>realtimePublisher(message)});
  return {
    router,service,db,device,onMessage,tick,connected,
    setRealtimePublisher(publish){realtimePublisher=typeof publish==='function'?publish:()=>{};},
    async close(){clearInterval(timer);if(client)await new Promise(resolve=>client.end(true,resolve));await db.close?.();},
  };
}
