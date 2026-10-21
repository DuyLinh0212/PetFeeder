import express from 'express';
import mqtt from 'mqtt';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {Service} from './service.js';
import {Storage} from './storage.js';
import {migrateLegacy} from './legacyMigration.js';
import {Invalid,object,number,identifier,dispensedStatuses} from './policy.js';

const dayNames=['CN','T2','T3','T4','T5','T6','T7'];
export function toSchedule(s,id){
  object(s);
  if(typeof s.time!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(s.time))throw new Invalid('INVALID_FIELD','time');
  if(!Array.isArray(s.days)||s.days.some(d=>!dayNames.includes(d)))throw new Invalid('INVALID_FIELD','days');
  if(typeof s.name!=='string'||s.name.length>80)throw new Invalid('INVALID_FIELD','name');
  const [hour,minute]=s.time.split(':').map(Number);
  return {schedule_id:id,name:s.name,hour,minute,target_portion_g:s.portion_g,days:s.days.map(d=>dayNames.indexOf(d)),enabled:s.enabled};
}
export function fromSchedule(s){return {id:s.schedule_id,name:s.name||'Lịch cho ăn',time:`${String(s.hour).padStart(2,'0')}:${String(s.minute).padStart(2,'0')}`,portion_g:s.target_portion_g,days:s.days.map(d=>dayNames[d]),enabled:s.enabled};}

// The main application keeps its REST envelopes and screen layout. Long's service
// is the single source of commands/history, rather than a second device or backend.
export function createIntegration({dataDir,legacyFile,brokerUrl,prefix='duylinh0212/petfeeder/v1',clock=()=>Math.floor(Date.now()/1000),transport:injected}={}){
  const db=new Storage(resolve(dataDir||process.env.DATA_DIR||fileURLToPath(new URL('../../data/main/',import.meta.url)),'backend.sqlite'));
  try {migrateLegacy(db,legacyFile??(dataDir||process.env.DATA_DIR?null:fileURLToPath(new URL('../../data/database.json',import.meta.url))));}
  catch(error){db.close();throw error;}
  let service,client;
  const transport=injected||{mode:'MQTT',send(kind,body){
    if(!client?.connected)return false;
    client.publish(`${prefix}/${kind}`,JSON.stringify(body),{qos:1,retain:false});return true;
  }};
  service=new Service(db,transport,clock);
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
  const router=express.Router();
  const ok=(res,data,extra={})=>res.json({success:true,data,...extra});
  function history(){
    const hidden=new Set(db.get('hidden_history')||[]);
    const current=db.all('commands').map(c=>({
      ...c,id:c.command_id,timestamp:new Date((c.occurred_at||c.updated_at||c.created_at)*1000).toISOString(),
      trigger_source:(c.source||'ESP32').toLowerCase(),message:c.error_code||c.status,duration_ms:0,
    }));
    return [...current,...db.all('legacy_history')].filter(r=>!hidden.has(r.id))
      .sort((a,b)=>Date.parse(b.timestamp)-Date.parse(a.timestamp));
  }
  function device(){
    const s=service.state(),h=s.device||{};
    const latest=[...db.all('commands').map(c=>({...c,timestamp:new Date((c.occurred_at||c.updated_at||c.created_at)*1000).toISOString()})),...db.all('legacy_history')]
      .filter(c=>dispensedStatuses.has(c.status)&&typeof c.actual_weight_g==='number'&&c.actual_weight_g>0).sort((a,b)=>Date.parse(b.timestamp)-Date.parse(a.timestamp))[0];
    return {device_id:h.device_id||'petfeeder_01',online:s.connection!=='OFFLINE',mqtt_connected:injected?true:!!client?.connected,
      system_status:s.connection==='BUSY'?'DANG CHO AN...':s.connection==='OFFLINE'?'NGOAI TUYEN':h.status||'SAN SANG',
      food_level_percent:h.food_level_percent??null,distance_cm:h.distance_cm??null,bowl_weight_g:h.weight_g??null,
      sensor_mode:h.sensor_mode||'UNKNOWN',ip_address:h.ip||'',wifi_rssi:h.rssi??0,
      last_seen:h.received_at?new Date(h.received_at*1000).toISOString():null,
      last_feed_time:latest?.timestamp??null,last_feed_portion_g:latest?.actual_weight_g??0,
      last_feed_status:latest?.status||'CHUA_CHO_AN',safe_interval_sec:s.config.min_interval_s,
      empty_threshold_cm:s.config.empty_threshold_cm,max_portion_g:s.config.max_portion_g,
      bowl_capacity_g:s.config.bowl_capacity_g,locked:h.locked??true,time_valid:h.time_valid??false,daily:s.daily};
  }
  const legacyConfig=()=>({...service.settings(),safe_interval_sec:service.settings().min_interval_s});
  function configure(input){
    const patch={...object(input)};
    if('safe_interval_sec' in patch){patch.min_interval_s=patch.safe_interval_sec;delete patch.safe_interval_sec;}
    if('verify_refill' in patch){
      if(typeof patch.verify_refill!=='boolean')throw new Invalid('INVALID_FIELD','verify_refill');
      if(patch.verify_refill){patch.food_confirmed=true;patch.food_label=patch.food_label||service.settings().food_label||'Chủ xác nhận';}
      delete patch.verify_refill;
    }
    return service.configure(patch);
  }
  router.get('/id',(req,res)=>res.json({command_id:service.id(),now:clock(),ttl_s:service.settings().command_ttl_s}));
  router.get('/state',(req,res)=>res.json(service.state()));
  router.get('/history',(req,res)=>res.json({commands:db.all('commands'),events:db.all('events')}));
  router.post('/config',(req,res)=>res.json(configure(req.body)));
  router.get('/device/status',(req,res)=>ok(res,device()));
  router.get('/device/config',(req,res)=>ok(res,legacyConfig()));
  router.put('/device/config',(req,res)=>{configure(req.body);ok(res,legacyConfig());});
  router.post('/feeding',(req,res)=>res.json(service.feed(req.body)));
  router.post('/feeding/feed',(req,res)=>{
    const b=object(req.body);
    if(!b.command_id)throw new Invalid('COMMAND_ID_REQUIRED','command_id');
    const command={command_id:b.command_id,source:'APP',target_portion_g:b.portion,
      override:b.override,created_at:b.created_at,expires_at:b.expires_at,...(b.retry_of===undefined?{}:{retry_of:b.retry_of})};
    const result=service.feed(command);
    const rejected=result.status==='REJECTED'||result.status==='COMMAND_EXPIRED';
    res.status(rejected?409:200).json({success:!rejected,code:result.error_code,message:rejected?result.error_code:'Đã nhận yêu cầu; chờ ESP32 xác nhận kết quả.',data:result});
  });
  router.get('/feeding/history',(req,res)=>{
    const limit=req.query.limit===undefined?50:Number(req.query.limit);number(limit,1,200,'limit',true);
    const rows=history().slice(0,limit);ok(res,rows,{count:rows.length});
  });
  router.delete('/feeding/history',(req,res)=>{
    // Hide rows from the view without deleting idempotency keys or daily totals.
    db.put('hidden_history','state',[...db.all('commands').map(c=>c.command_id),...db.all('legacy_history').map(r=>r.id)]);ok(res,[]);
  });
  router.get('/schedules',(req,res)=>{const rows=(db.get('schedules')||[]).map(fromSchedule);ok(res,rows,{count:rows.length});});
  router.post('/schedules',(req,res)=>{
    if(Array.isArray(req.body.schedules)){service.setSchedules(req.body.schedules);return ok(res,service.state().schedules);}
    const row=toSchedule(req.body,`sch_${service.id()}`);service.setSchedules([...(db.get('schedules')||[]),row]);
    res.status(201).json({success:true,data:fromSchedule(row),message:'Đã lưu lịch; chờ ESP32 áp dụng.'});
  });
  router.put('/schedules/:id',(req,res)=>{
    const rows=db.get('schedules')||[],index=rows.findIndex(s=>s.schedule_id===req.params.id);
    if(index<0)return res.status(404).json({success:false,message:'Không tìm thấy lịch'});
    const row=toSchedule({...fromSchedule(rows[index]),...object(req.body)},req.params.id);
    rows[index]=row;service.setSchedules(rows);ok(res,fromSchedule(row));
  });
  router.patch('/schedules/:id/toggle',(req,res)=>{
    const rows=db.get('schedules')||[],row=rows.find(s=>s.schedule_id===req.params.id);
    if(!row)return res.status(404).json({success:false,message:'Không tìm thấy lịch'});
    row.enabled=!row.enabled;service.setSchedules(rows);ok(res,fromSchedule(row));
  });
  router.delete('/schedules/:id',(req,res)=>{
    const rows=db.get('schedules')||[],next=rows.filter(s=>s.schedule_id!==req.params.id);
    if(next.length===rows.length)return res.status(404).json({success:false,message:'Không tìm thấy lịch'});
    service.setSchedules(next);ok(res,[]);
  });
  function alerts(){
    const read=new Set(db.get('read_alerts')||[]),hidden=new Set(db.get('hidden_alerts')||[]);
    const current=db.all('events').filter(e=>!['ACCEPTED','DISPENSING','SUCCESS','CONFIG_APPLIED'].includes(e.status)).map(e=>({
      id:e.event_id,timestamp:new Date(e.occurred_at*1000).toISOString(),level:['JAM_ERROR','SENSOR_ERROR','INTERRUPTED'].includes(e.status)?'error':'warning',title:e.status,message:e.error_code||e.status,read:read.has(e.event_id)}));
    return [...current,...db.all('legacy_alerts').map(a=>({...a,read:a.read||read.has(a.id)}))]
      .filter(a=>!hidden.has(a.id)).sort((a,b)=>Date.parse(b.timestamp)-Date.parse(a.timestamp));
  }
  router.get('/notifications',(req,res)=>ok(res,alerts()));
  router.patch('/notifications/:id/read',(req,res)=>{
    identifier(req.params.id,'event_id');db.put('read_alerts','state',[...new Set([...(db.get('read_alerts')||[]),req.params.id])]);ok(res,true);
  });
  router.delete('/notifications',(req,res)=>{db.put('hidden_alerts','state',[...db.all('events').map(e=>e.event_id),...db.all('legacy_alerts').map(a=>a.id)]);ok(res,true);});
  router.use((err,req,res,next)=>res.status(err.http||500).json({success:false,code:err.code||'INTERNAL_ERROR',field:err.field||'',message:err.message}));
  return {router,service,db,device,onMessage,tick,connected:()=>injected?true:!!client?.connected,close(){clearInterval(timer);client?.end(true);db.close();}};
}
