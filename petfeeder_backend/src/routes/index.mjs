import express from 'express';
import {Invalid,object,number,identifier,dispensedStatuses} from '../domain/feedingPolicy.mjs';

const dayNames=['CN','T2','T3','T4','T5','T6','T7'];
const alertTitles={
  REJECTED:'Không thể cho ăn',COMMAND_EXPIRED:'Lệnh đã hết hạn',BLOCKED_DUPLICATE:'Đã chặn lệnh gửi lặp',
  TIME_INVALID:'Giờ thiết bị chưa đồng bộ',UNKNOWN_PET:'Chưa xác nhận thú cưng',UNVERIFIED:'Chưa xác nhận thức ăn',
  COOLDOWN:'Đang trong thời gian chờ',DAILY_LIMIT:'Đã hết hạn mức thức ăn hôm nay',
  DAILY_FEED_LIMIT:'Đã đạt số lần cho ăn tối đa',BOWL_FULL:'Bát đã gần đầy',BOWL_MISSING:'Không thấy bát thức ăn',
  FOOD_EMPTY:'Hộp thức ăn đã hết',SENSOR_ERROR:'Cảm biến gặp sự cố',JAM_ERROR:'Thức ăn bị kẹt',
  INTERRUPTED:'Phiên cấp bị gián đoạn',OVER_PORTION:'Lượng cấp vượt khẩu phần',PARTIAL:'Lượng cấp chưa đủ',
  TIMEOUT:'Thiết bị chờ quá lâu',RECONCILIATION_REQUIRED:'Cần kiểm tra thiết bị',SAFETY_LOCKOUT:'Thiết bị đang khóa an toàn',
  CONFIG_APPLIED:'Thiết bị đã đồng bộ cấu hình',MANUAL_REFILL:'Đã thêm thức ăn vào bát',WEIGHT_DECREASED:'Khối lượng bát đã giảm',
  FOOD_LEFT:'Thức ăn còn trong bát',FOOD_STALE:'Thức ăn trong bát đã để lâu',MISSED_SCHEDULE:'Đã bỏ lỡ lịch cho ăn',
};
const alertMessages={
  TIME_INVALID:'Giờ ESP32 đang chậm hoặc chưa đồng bộ với máy chủ. Nếu dùng Wokwi, đặt tốc độ mô phỏng về 100% rồi khởi động lại.',
  BLOCKED_DUPLICATE:'Thiết bị đã nhận mã lệnh này trước đó và chặn lần gửi lại để tránh cấp thức ăn hai lần.',
  UNKNOWN_PET:'Hãy xác nhận thú cưng trước khi cho ăn.',
  UNVERIFIED:'Vào Cài đặt, nhập loại thức ăn và xác nhận đã kiểm tra.',
  COOLDOWN:'Hãy đợi hết khoảng chờ bảo vệ rồi thử lại.',
  DAILY_LIMIT:'Đã đạt tổng lượng thức ăn tối đa trong ngày.',
  DAILY_FEED_LIMIT:'Đã đạt số bữa tối đa trong ngày.',
  BOWL_FULL:'Bát không còn đủ chỗ cho khẩu phần mới.',
  BOWL_MISSING:'Đặt bát lên cân và kiểm tra kết nối HX711.',
  FOOD_EMPTY:'Hãy bổ sung thức ăn vào hộp.',
  SENSOR_ERROR:'Kiểm tra cảm biến và chờ số đo ổn định.',
  JAM_ERROR:'Kiểm tra đường trượt thức ăn và cơ cấu servo.',
  RECONCILIATION_REQUIRED:'Kiểm tra thiết bị rồi xác nhận đã kiểm tra trước khi cho ăn tiếp.',
  SAFETY_LOCKOUT:'Mở Cài đặt để kiểm tra trạng thái khóa an toàn.',
  COMMAND_EXPIRED:'Lệnh đã hết hạn và không được thực hiện. Tạo yêu cầu mới sau khi kiểm tra trạng thái.',
  OVER_PORTION:'Thiết bị đã dừng để tránh cấp thêm quá lượng đặt.',
  PARTIAL:'Kiểm tra lượng thực cấp trước khi yêu cầu cấp bù.',
  INTERRUPTED:'Kiểm tra bát và thiết bị trước khi tiếp tục.',
  TIMEOUT:'Kiểm tra thiết bị và cân trước khi gửi yêu cầu khác.',
};
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
    return {device_id:h.device_id||'petfeeder_01',online:s.connection!=='OFFLINE',mqtt_connected:connected(),
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
  router.get('/pets/demo',(req,res)=>ok(res,db.get('camera_pet')));
  router.post('/pets/demo',(req,res)=>{
    const b=object(req.body);
    if(typeof b.name!=='string'||!b.name.trim()||b.name.trim().length>60)throw new Invalid('INVALID_FIELD','name');
    const old=db.get('camera_pet');
    const pet={pet_id:old?.pet_id||service.settings().registered_pet_id||`pet-${service.id()}`,name:b.name.trim()};
    service.configure({registered_pet_id:pet.pet_id,require_pet:true});db.put('camera_pet','state',pet);
    ok(res,pet);
  });
  router.get('/identity',(req,res)=>ok(res,service.state().identity));
  router.post('/identity/camera-demo',(req,res)=>res.status(410).json({success:false,code:'MANUAL_VERIFICATION_REMOVED',message:'Chỉ nhận kết quả từ YOLO xử lý ảnh.'}));
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
    const reason=result.error_code;
    const explanation=alertMessages[reason]||'Hệ thống chưa thể thực hiện yêu cầu. Hãy kiểm tra thiết bị và thử lại sau.';
    const message=result.status==='DELIVERY_UNKNOWN'
      ?result.delivery_attempted
        ?'Đã gửi lại đúng mã lệnh để thiết bị tra kết quả. Chưa xác nhận lượng thức ăn đã cấp.'
        :'Chưa gửi lại được qua MQTT. Giữ nguyên mã lệnh và thử lại khi kết nối hoạt động.'
      :rejected?`${explanation} (${reason})`:'Đã nhận yêu cầu; đang chờ ESP32 xác nhận kết quả.';
    res.status(rejected?409:200).json({success:!rejected,code:reason,
      message,data:result});
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
    const current=db.all('events').filter(e=>!['ACCEPTED','DISPENSING','SUCCESS','CONFIG_APPLIED','CLOCK_SYNCED'].includes(e.status)).map(e=>({
      id:e.event_id,timestamp:new Date(e.occurred_at*1000).toISOString(),level:['JAM_ERROR','SENSOR_ERROR','INTERRUPTED','OVER_PORTION','TIMEOUT'].includes(e.status)?'error':'warning',
      title:alertTitles[e.error_code]||alertTitles[e.status]||'Cảnh báo thiết bị',
      message:`${alertMessages[e.error_code]||alertMessages[e.status]||'Thiết bị đã ghi nhận một sự kiện cần chú ý.'} (${e.error_code||e.status})`,
      code:e.error_code||e.status,read:read.has(e.event_id)}));
    return [...current,...db.all('legacy_alerts').map(a=>({...a,read:a.read||read.has(a.id)}))]
      .filter(a=>!hidden.has(a.id)).sort((a,b)=>Date.parse(b.timestamp)-Date.parse(a.timestamp));
  }
  router.get('/notifications',(req,res)=>ok(res,alerts()));
  router.patch('/notifications/:id/read',(req,res)=>{
    identifier(req.params.id,'event_id');db.put('read_alerts','state',[...new Set([...(db.get('read_alerts')||[]),req.params.id])]);ok(res,true);
  });
  router.delete('/notifications',(req,res)=>{db.put('hidden_alerts','state',[...db.all('events').map(e=>e.event_id),...db.all('legacy_alerts').map(a=>a.id)]);ok(res,true);});
  router.use((err,req,res,next)=>res.status(err.http||500).json({success:false,code:err.code||'INTERNAL_ERROR',field:err.field||'',message:err.message}));
  return {router,device};
}
