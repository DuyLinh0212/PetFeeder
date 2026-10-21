import express from 'express';
import {performance} from 'node:perf_hooks';
import {Invalid,object,identifier} from '../domain/feedingPolicy.mjs';

const dayNames=['CN','T2','T3','T4','T5','T6','T7'];
const rejectionMessages={
  TIME_INVALID:'Giờ thiết bị chưa đồng bộ với máy chủ.',
  UNKNOWN_PET:'Chưa xác nhận được chó/mèo từ camera. Cần bật camera và chờ nhận diện mới.',
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

export function toSchedule(s,id){
  object(s);
  if(typeof s.time!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(s.time))throw new Invalid('INVALID_FIELD','time');
  if(!Array.isArray(s.days)||s.days.some(d=>!dayNames.includes(d)))throw new Invalid('INVALID_FIELD','days');
  if(typeof s.name!=='string'||s.name.length>80)throw new Invalid('INVALID_FIELD','name');
  const [hour,minute]=s.time.split(':').map(Number);
  return {schedule_id:id,name:s.name,hour,minute,target_portion_g:s.portion_g,days:s.days.map(d=>dayNames.indexOf(d)),enabled:s.enabled};
}
export function fromSchedule(s){return {id:s.schedule_id,name:s.name||'Lịch cho ăn',time:`${String(s.hour).padStart(2,'0')}:${String(s.minute).padStart(2,'0')}`,portion_g:s.target_portion_g,days:s.days.map(d=>dayNames[d]),enabled:s.enabled};}

export function createApiRouter({db,service,clock,connected}){
  const router=express.Router();
  let lastFeedRequestAt=-Infinity;
  const ok=(res,data,extra={})=>res.json({success:true,data,...extra});
  function device(){
    const s=service.state(),h=s.device||{};
    return {device_id:h.device_id||'petfeeder_01',online:s.connection!=='OFFLINE',mqtt_connected:connected(),
      system_status:s.connection==='BUSY'?'DANG CHO AN...':s.connection==='OFFLINE'?'NGOAI TUYEN':h.status||'SAN SANG',
      bowl_weight_g:h.weight_g??null,food_level_percent:h.food_level_percent??null,
      distance_cm:h.distance_cm??null,ip_address:h.ip||'',wifi_rssi:h.rssi??0,
      min_interval_s:s.config.min_interval_s,max_portion_g:s.config.max_portion_g,
      daily_limit_g:s.config.daily_limit_g,max_daily_feeds:s.config.max_daily_feeds,
      bowl_capacity_g:s.config.bowl_capacity_g,require_pet:s.config.require_pet,
      daily:s.daily,locked:h.locked??true,time_valid:h.time_valid??false,
      sensor_mode:h.sensor_mode||'UNKNOWN',last_seen:h.received_at?new Date(h.received_at*1000).toISOString():null};
  }
  router.get('/id',(req,res)=>res.json({command_id:service.id(),now:clock(),ttl_s:service.settings().command_ttl_s}));
  router.get('/commands/:id',(req,res)=>{
    identifier(req.params.id,'command_id');
    const row=db.get('commands',req.params.id);
    if(!row)return res.status(404).json({success:false,code:'COMMAND_NOT_FOUND',message:'Chưa có kết quả cho mã lệnh này.'});
    return ok(res,row);
  });
  router.get('/device/status',(req,res)=>ok(res,device()));
  router.get('/device/config',(req,res)=>ok(res,service.settings()));
  router.put('/device/config',(req,res)=>ok(res,service.configure(req.body)));
  router.post('/feeding/feed',(req,res)=>{
    const b=object(req.body);
    for(const key of Object.keys(b))if(!['command_id','portion','created_at','expires_at'].includes(key))throw new Invalid('UNKNOWN_FIELD',key);
    if(!b.command_id)throw new Invalid('COMMAND_ID_REQUIRED','command_id');
    const requestAt=performance.now();
    const elapsed=requestAt-lastFeedRequestAt;
    if(elapsed<500){
      const retryAfterMs=Math.max(1,Math.ceil(500-elapsed));
      return res.status(429).json({success:false,code:'RATE_LIMITED',retry_after_ms:retryAfterMs,
        message:`Chỉ nhận một yêu cầu cho ăn trong mỗi 0,5 giây. Thử lại sau ${retryAfterMs} ms.`});
    }
    lastFeedRequestAt=requestAt;
    const result=service.feed({command_id:b.command_id,source:'APP',target_portion_g:b.portion,
      created_at:b.created_at,expires_at:b.expires_at});
    const failed=failedCommandStatuses.has(result.status);
    const reason=result.error_code;
    const message=result.status==='DELIVERY_UNKNOWN'
      ?'Máy chủ chưa nhận được kết quả cuối từ thiết bị. Hãy kiểm tra trạng thái trước khi quyết định cấp thêm.'
      :result.status==='SUCCESS'?'Thiết bị đã xác nhận cấp đủ khẩu phần.'
      :failed?`${rejectionMessages[reason]||rejectionMessages[result.status]||'Hệ thống chưa thể thực hiện yêu cầu.'}${reason?` (${reason})`:''}`
      :'Đã nhận yêu cầu; đang chờ ESP32 xác nhận kết quả.';
    res.status(failed?409:200).json({success:!failed,code:reason||result.status,message,data:result});
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
  router.use((err,req,res,next)=>res.status(err.http||500).json({success:false,code:err.code||'INTERNAL_ERROR',field:err.field||'',message:err.message}));
  return {router,device};
}
