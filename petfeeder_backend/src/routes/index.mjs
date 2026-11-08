import express from 'express';
import {randomUUID} from 'node:crypto';
import {performance} from 'node:perf_hooks';
import {Invalid,object,identifier} from '../domain/feedingPolicy.mjs';

const dayNames=['CN','T2','T3','T4','T5','T6','T7'];
const rejectionMessages={
  TIME_INVALID:'Giờ thiết bị chưa đồng bộ với máy chủ.',
  COOLDOWN:'Hãy đợi hết khoảng chờ bảo vệ rồi thử lại.',
  DAILY_LIMIT:'Đã đạt tổng lượng thức ăn tối đa trong ngày.',
  DAILY_FEED_LIMIT:'Đã đạt số bữa tối đa trong ngày.',
  BOWL_FULL:'Bát không còn đủ chỗ cho khẩu phần mới.',
  BOWL_MISSING:'Không phát hiện bát trên cân. Kiểm tra bát và cân HX711.',
  SENSOR_ERROR:'Cân chưa ổn định hoặc không đọc được số đo.',
  BUSY:'Thiết bị đang thực hiện một phiên cấp khác.',
  COMMAND_EXPIRED:'Lệnh đã hết hạn và không được thực hiện.',
  COMMAND_ID_CONFLICT:'Mã lệnh cũ được gửi với nội dung khác.',
  RECONCILIATION_REQUIRED:'Cần kiểm tra thiết bị trước khi cho ăn tiếp.',
  OUTBOX_FULL:'Thiết bị đang giữ đầy hàng đợi offline; lịch và nút vật lý vẫn hoạt động.',
  PARTIAL:'Thiết bị đã dừng trước khi đạt đủ lượng đặt.',
  OVER_PORTION:'Thiết bị đã dừng để tránh cấp thêm quá lượng đặt.',
  INTERRUPTED:'Phiên cấp bị gián đoạn; kiểm tra bát và thiết bị trước khi tiếp tục.',
  TIMEOUT:'Thiết bị đã dừng sau khi hết thời gian cấp tối đa.',
  MQTT_UNAVAILABLE:'Máy chủ không kết nối được MQTT nên chưa gửi lệnh tới thiết bị.',
};
const failedCommandStatuses=new Set([
  'PARTIAL','OVER_PORTION','REJECTED','COMMAND_EXPIRED','SENSOR_ERROR',
  'BOWL_MISSING','TIMEOUT','INTERRUPTED','DELIVERY_FAILED',
]);
const asyncRoute=handler=>(req,res,next)=>Promise.resolve(handler(req,res,next)).catch(next);

export function toSchedule(s,id){
  object(s);
  if(typeof s.time!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(s.time))throw new Invalid('INVALID_FIELD','time');
  if(!Array.isArray(s.days)||s.days.some(d=>!dayNames.includes(d)))throw new Invalid('INVALID_FIELD','days');
  if(typeof s.name!=='string'||s.name.length>80)throw new Invalid('INVALID_FIELD','name');
  const [hour,minute]=s.time.split(':').map(Number);
  return {schedule_id:id,name:s.name,hour,minute,target_portion_g:s.portion_g,days:s.days.map(d=>dayNames.indexOf(d)),enabled:s.enabled};
}

export function fromSchedule(s){
  return {id:s.schedule_id,name:s.name||'Lịch cho ăn',time:`${String(s.hour).padStart(2,'0')}:${String(s.minute).padStart(2,'0')}`,
    portion_g:s.target_portion_g,days:s.days.map(d=>dayNames[d]),enabled:s.enabled};
}

function validAddress(value){
  if(typeof value!=='string'||value.length>512)throw new Invalid('INVALID_FIELD','connection_address');
  const address=value.trim().replace(/\/+$/,'');
  let url;
  try { url=new URL(address); } catch { throw new Invalid('INVALID_FIELD','connection_address'); }
  if(!['http:','https:'].includes(url.protocol)||!url.hostname||url.username||url.password||url.search||url.hash)
    throw new Invalid('INVALID_FIELD','connection_address');
  return address;
}

export function createApiRouter({db,service,clock,connected,publishRealtime=()=>{},
  pushNotifications={enabled:false,register:async()=>({registered:true,push_enabled:false}),unregister:async()=>({registered:false})}}){
  const router=express.Router();
  let lastFeedRequestAt=-Infinity;
  const recoveryRetries=new Map();
  const ok=(res,data,extra={})=>res.json({success:true,data,...extra});

  async function device(){
    const s=await service.state(),h=s.device||{};
    const retryable=s.commands.find(row=>row.status==='INTERRUPTED'&&
      row.error_code==='POWER_OUTAGE_RETRY_REQUIRED'&&!row.recovery_retry_command_id&&
      typeof row.target_portion_g==='number'&&typeof row.actual_weight_g==='number'&&
      row.target_portion_g-row.actual_weight_g>=1);
    const recovery=retryable?{
      command_id:retryable.command_id,target_portion_g:retryable.target_portion_g,
      actual_weight_g:retryable.actual_weight_g,
      remaining_portion_g:Math.round((retryable.target_portion_g-retryable.actual_weight_g)*10)/10,
      occurred_at:retryable.occurred_at??null,
    }:null;
    return {device_id:h.device_id||'petfeeder_01',online:s.connection!=='OFFLINE',mqtt_connected:connected(),
      system_status:s.connection==='BUSY'?'DANG CHO AN...':s.connection==='OFFLINE'?'NGOAI TUYEN':h.status||'SAN SANG',
      bowl_weight_g:h.weight_g??null,food_level_percent:h.food_level_percent??null,
      distance_cm:h.distance_cm??null,ip_address:h.ip||'',wifi_rssi:h.rssi??0,
      pending_events:h.outbox??0,outbox_overflow_count:h.outbox_overflow_count??0,
      min_interval_s:s.config.min_interval_s,max_portion_g:s.config.max_portion_g,
      daily_limit_g:s.config.daily_limit_g,max_daily_feeds:s.config.max_daily_feeds,
      bowl_capacity_g:s.config.bowl_capacity_g,daily:s.daily,locked:h.locked??true,
      time_valid:h.time_valid??false,sensor_mode:h.sensor_mode||'UNKNOWN',
      recovery_required:recovery,
      last_seen:h.received_at?new Date(h.received_at*1000).toISOString():null};
  }

  router.get('/id',asyncRoute(async(req,res)=>res.json({command_id:service.id(),now:clock(),ttl_s:(await service.settings()).command_ttl_s})));
  router.get('/commands/:id',asyncRoute(async(req,res)=>{
    identifier(req.params.id,'command_id');
    const row=await db.get('commands',req.params.id);
    if(!row)return res.status(404).json({success:false,code:'COMMAND_NOT_FOUND',message:'Chưa có kết quả cho mã lệnh này.'});
    return ok(res,row);
  }));
  router.get('/feeding/history',asyncRoute(async(req,res)=>{
    const requested=Number.parseInt(req.query.limit,10);
    const limit=Number.isInteger(requested)?Math.min(100,Math.max(1,requested)):50;
    let records;
    if(db.history)records=await db.history(limit);
    else {
      const [commands,legacyRows]=await Promise.all([db.all('commands'),db.all('legacy_history')]);
      const commandRecords=commands.map(row=>({
        command_id:row.command_id,source:row.source||'APP',target_portion_g:row.target_portion_g??null,
        actual_weight_g:row.actual_weight_g??null,status:row.status||'UNKNOWN',error_code:row.error_code||null,
        occurred_at:row.occurred_at??row.updated_at??row.created_at??null,
      }));
      const legacyRecords=legacyRows.map((row,index)=>{
        const parsed=typeof row.timestamp==='number'?row.timestamp:Date.parse(row.timestamp)/1000;
        const actual=row.actual_weight_g??row.actual_g??null;
        return {command_id:row.command_id||row.id||`legacy-${index}`,source:row.source||'APP',
          target_portion_g:row.target_portion_g??row.portion_g??row.portion??null,actual_weight_g:actual,
          status:row.status||(typeof actual==='number'?'SUCCESS':'UNKNOWN'),error_code:row.error_code||null,
          occurred_at:row.occurred_at??(Number.isFinite(parsed)?parsed:null)};
      });
      records=[...commandRecords,...legacyRecords].sort((a,b)=>(b.occurred_at||0)-(a.occurred_at||0)).slice(0,limit);
    }
    const state=await service.state();
    return ok(res,{records,daily:state.daily},{count:records.length});
  }));
  router.get('/device/status',asyncRoute(async(req,res)=>ok(res,await device())));
  router.get('/device/config',asyncRoute(async(req,res)=>ok(res,await service.settings())));
  router.post('/notifications/register',asyncRoute(async(req,res)=>{
    const body=object(req.body);
    for(const key of Object.keys(body))if(!['fid','installation_id','platform'].includes(key))throw new Invalid('UNKNOWN_FIELD',key);
    if(typeof body.fid!=='string'||body.fid.length<20||body.fid.length>256||/\s/.test(body.fid))
      throw new Invalid('INVALID_FIELD','fid');
    identifier(body.installation_id,'installation_id');
    if(!['android','ios'].includes(body.platform))throw new Invalid('INVALID_FIELD','platform');
    const state=await service.state();
    const deviceId=state.device?.device_id||'petfeeder_01';
    return ok(res,await pushNotifications.register({fid:body.fid,deviceId,
      installationId:body.installation_id,platform:body.platform}));
  }));
  router.delete('/notifications/register',asyncRoute(async(req,res)=>{
    const body=object(req.body);
    for(const key of Object.keys(body))if(!['fid','installation_id','platform'].includes(key))throw new Invalid('UNKNOWN_FIELD',key);
    if(typeof body.fid!=='string'||body.fid.length<20||body.fid.length>256||/\s/.test(body.fid))
      throw new Invalid('INVALID_FIELD','fid');
    identifier(body.installation_id,'installation_id');
    if(!['android','ios'].includes(body.platform))throw new Invalid('INVALID_FIELD','platform');
    const state=await service.state();
    const deviceId=state.device?.device_id||'petfeeder_01';
    return ok(res,await pushNotifications.unregister({deviceId,installationId:body.installation_id}));
  }));
  router.put('/device/config',asyncRoute(async(req,res)=>{
    const result=await service.configure(req.body);
    publishRealtime({type:'config_updated',data:result});
    return ok(res,result);
  }));
  router.get('/device/connection',asyncRoute(async(req,res)=>ok(res,await db.get('connection')||{connection_address:null})));
  router.put('/device/connection',asyncRoute(async(req,res)=>{
    const body=object(req.body);
    for(const key of Object.keys(body))if(key!=='connection_address')throw new Invalid('UNKNOWN_FIELD',key);
    const result={connection_address:validAddress(body.connection_address),updated_at:new Date(clock()*1000).toISOString()};
    await db.put('connection','state',result);
    publishRealtime({type:'connection_updated',data:result});
    return ok(res,result);
  }));
  router.post('/feeding/feed',asyncRoute(async(req,res)=>{
    const b=object(req.body);
    for(const key of Object.keys(b))if(!['command_id','portion','created_at','expires_at'].includes(key))throw new Invalid('UNKNOWN_FIELD',key);
    if(!b.command_id)throw new Invalid('COMMAND_ID_REQUIRED','command_id');
    const requestAt=performance.now(),elapsed=requestAt-lastFeedRequestAt;
    if(elapsed<500){
      const retryAfterMs=Math.max(1,Math.ceil(500-elapsed));
      return res.status(429).json({success:false,code:'RATE_LIMITED',retry_after_ms:retryAfterMs,
        message:`Chỉ nhận một yêu cầu cho ăn trong mỗi 0,5 giây. Thử lại sau ${retryAfterMs} ms.`});
    }
    lastFeedRequestAt=requestAt;
    const result=await service.feed({command_id:b.command_id,source:'APP',target_portion_g:b.portion,created_at:b.created_at,expires_at:b.expires_at});
    publishRealtime({type:'feeding_command',data:result});
    const failed=failedCommandStatuses.has(result.status),reason=result.error_code;
    const message=result.status==='DELIVERY_UNKNOWN'
      ?'Máy chủ chưa nhận được kết quả cuối từ thiết bị. Hãy kiểm tra trạng thái trước khi quyết định cấp thêm.'
      :result.status==='SUCCESS'?'Thiết bị đã xác nhận cấp đủ khẩu phần.'
      :failed?`${rejectionMessages[reason]||rejectionMessages[result.status]||'Hệ thống chưa thể thực hiện yêu cầu.'}${reason?` (${reason})`:''}`
      :'Đã nhận yêu cầu; đang chờ ESP32 xác nhận kết quả.';
    return res.status(failed?409:200).json({success:!failed,code:reason||result.status,message,data:result});
  }));
  router.post('/feeding/recovery/:commandId/retry',asyncRoute(async(req,res)=>{
    const originalId=identifier(req.params.commandId,'command_id');
    const attempt=async()=>{
      const original=await db.get('commands',originalId);
      if(!original)return {status:404,body:{success:false,code:'COMMAND_NOT_FOUND',message:'Không tìm thấy phiên cấp bị gián đoạn.'}};
      if(original.recovery_retry_command_id){
        const retry=await db.get('commands',original.recovery_retry_command_id);
        return {status:200,body:{success:true,code:'RETRY_ALREADY_SENT',message:'Lệnh cấp lại đã được gửi trước đó.',data:retry}};
      }
      if(original.status!=='INTERRUPTED'||original.error_code!=='POWER_OUTAGE_RETRY_REQUIRED')
        return {status:409,body:{success:false,code:'RECOVERY_NOT_AVAILABLE',message:'Phiên này không còn yêu cầu cấp lại.'}};
      if(typeof original.target_portion_g!=='number'||typeof original.actual_weight_g!=='number')
        return {status:409,body:{success:false,code:'RECOVERY_WEIGHT_UNKNOWN',message:'Chưa có số cân đáng tin cậy để tính phần còn thiếu.'}};
      const portion=Math.round((original.target_portion_g-original.actual_weight_g)*10)/10;
      if(portion<1)return {status:409,body:{success:false,code:'RECOVERY_COMPLETE',message:'Số cân cho thấy khẩu phần đã đủ; không cần cấp lại.'}};
      const settings=await service.settings(),createdAt=clock();
      const command={command_id:randomUUID(),source:'APP',target_portion_g:portion,
        created_at:createdAt,expires_at:createdAt+settings.command_ttl_s};
      const result=await service.feed(command);
      if(result.status==='QUEUED'||result.status==='PUBLISHED'||result.status==='ACCEPTED'){
        const latest=await db.get('commands',originalId)||original;
        await db.put('commands',originalId,{...latest,recovery_retry_command_id:command.command_id,
          recovery_retry_requested_at:clock()});
        publishRealtime({type:'feeding_command',data:result});
        publishRealtime({type:'recovery_retry',data:{original_command_id:originalId,command:result}});
        publishRealtime({type:'device_state',data:await device()});
        return {status:200,body:{success:true,code:'RECOVERY_RETRY_QUEUED',
          message:`Đã gửi lệnh cấp lại phần còn thiếu ${portion} g.`,data:{...result,remaining_portion_g:portion}}};
      }
      const reason=result.error_code||result.status;
      const message=rejectionMessages[reason]||'Chưa thể gửi lệnh cấp lại. Kiểm tra thiết bị rồi thử lại.';
      return {status:409,body:{success:false,code:reason,message,data:result}};
    };
    let pending=recoveryRetries.get(originalId);
    if(!pending){pending=attempt();recoveryRetries.set(originalId,pending);}
    try{
      const outcome=await pending;
      return res.status(outcome.status).json(outcome.body);
    }finally{
      if(recoveryRetries.get(originalId)===pending)recoveryRetries.delete(originalId);
    }
  }));
  router.get('/schedules',asyncRoute(async(req,res)=>{
    const rows=(await db.get('schedules')||[]).map(fromSchedule);
    return ok(res,rows,{count:rows.length});
  }));
  router.post('/schedules',asyncRoute(async(req,res)=>{
    if(Array.isArray(req.body.schedules)){
      await service.setSchedules(req.body.schedules);
      const state=await service.state();publishRealtime({type:'schedules_updated',data:state.schedules});
      return ok(res,state.schedules);
    }
    const existing=await db.get('schedules')||[];
    const row=toSchedule(req.body,`sch_${service.id()}`);
    await service.setSchedules([...existing,row]);
    publishRealtime({type:'schedules_updated',data:await db.get('schedules')});
    return res.status(201).json({success:true,data:fromSchedule(row),message:'Đã lưu lịch; chờ ESP32 áp dụng.'});
  }));
  router.put('/schedules/:id',asyncRoute(async(req,res)=>{
    const rows=await db.get('schedules')||[],index=rows.findIndex(s=>s.schedule_id===req.params.id);
    if(index<0)return res.status(404).json({success:false,message:'Không tìm thấy lịch'});
    const row=toSchedule({...fromSchedule(rows[index]),...object(req.body)},req.params.id);
    rows[index]=row;await service.setSchedules(rows);publishRealtime({type:'schedules_updated',data:rows});
    return ok(res,fromSchedule(row));
  }));
  router.patch('/schedules/:id/toggle',asyncRoute(async(req,res)=>{
    const rows=await db.get('schedules')||[],row=rows.find(s=>s.schedule_id===req.params.id);
    if(!row)return res.status(404).json({success:false,message:'Không tìm thấy lịch'});
    row.enabled=!row.enabled;await service.setSchedules(rows);publishRealtime({type:'schedules_updated',data:rows});
    return ok(res,fromSchedule(row));
  }));
  router.delete('/schedules/:id',asyncRoute(async(req,res)=>{
    const rows=await db.get('schedules')||[],next=rows.filter(s=>s.schedule_id!==req.params.id);
    if(next.length===rows.length)return res.status(404).json({success:false,message:'Không tìm thấy lịch'});
    await service.setSchedules(next);publishRealtime({type:'schedules_updated',data:next});
    return ok(res,[]);
  }));
  router.use((err,req,res,next)=>res.status(err.http||500).json({success:false,code:err.code||'INTERNAL_ERROR',field:err.field||'',message:err.message}));
  return {router,device};
}
