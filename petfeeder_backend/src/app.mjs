import mqtt from 'mqtt';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {FeedingService} from './services/feedingService.mjs';
import {Storage} from './storage/database.mjs';
import {migrateLegacy} from './storage/legacyMigration.mjs';
import {createApiRouter} from './routes/index.mjs';

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
    if(topic===`${prefix}/telemetry`)service.heartbeat(payload);
    else if(topic===`${prefix}/events`){
      service.event(payload); // SQLite commits before acknowledging the event.
      client?.publish(`${prefix}/ack`,JSON.stringify({event_id:payload.event_id}),{qos:1,retain:false});
    }
  }
  if(!injected){
    client=mqtt.connect(brokerUrl||process.env.MQTT_BROKER_URL||'mqtt://broker.emqx.io:1883',{
      clientId:`petfeeder-main-${process.pid}`,clean:true,reconnectPeriod:3000,
      username:process.env.MQTT_USERNAME,password:process.env.MQTT_PASSWORD,
    });
    client.on('connect',()=>client.subscribe([`${prefix}/events`,`${prefix}/telemetry`],{qos:1},()=>service.sync()));
    client.on('message',(topic,body,packet)=>{try{onMessage(topic,body,packet);}catch(e){console.error('[MQTT rejected]',e.message);}});
    client.on('error',e=>console.error('[MQTT]',e.message));
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
  return {router,service,db,device,onMessage,tick,connected,close(){clearInterval(timer);client?.end(true);db.close();}};
}
