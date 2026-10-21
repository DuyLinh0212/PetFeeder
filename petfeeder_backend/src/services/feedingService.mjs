import {randomUUID,createHash} from 'node:crypto';
import {defaults,config,command,schedules,terminal,dispensedStatuses,identifier,number,object,Invalid,sameCommand,dayKey} from '../domain/feedingPolicy.mjs';
export class FeedingService {
  constructor(store, transport, clock=()=>Math.floor(Date.now()/1000)) { this.store=store;this.transport=transport;this.clock=clock;this.identity=null; }
  settings(){return {...defaults,...this.store.get('config')};}
  observePet(detections,{issuedAt=this.clock(),confirmed=true,active=true}={}){
    const boxes=detections.filter(b=>['cat','dog'].includes(b.label)&&typeof b.confidence==='number'&&Number.isFinite(b.confidence)&&b.confidence>=0.5&&b.confidence<=1);
    const best=boxes.sort((a,b)=>b.confidence-a.confidence)[0];
    const now=this.clock(),matched=!!best&&confirmed&&now-issuedAt<3;
    this.identity={recognition_id:this.id(),pet_id:best?`species-${best.label}`:'unknown',pet_type:best?.label||null,
      camera_active:active,matched,confidence:best?.confidence||0,confidence_kind:'MODEL',source:'YOLO_PET_PRESENCE',issued_at:issuedAt,expires_at:issuedAt+5};
    this.transport.send('identity',this.identity);return this.identity;
  }
  revokePet(){return this.observePet([],{confirmed:false,active:false});}
  identityValid(){const p=this.identity;return !!p&&p.camera_active&&p.matched&&p.source==='YOLO_PET_PRESENCE'&&
    ['cat','dog'].includes(p.pet_type)&&p.confidence>=0.5&&p.issued_at<=this.clock()+2&&p.expires_at>this.clock();}
  configure(patch){const next=config({...this.settings(),...object(patch)});schedules(this.store.get('schedules')||[],next);this.store.put('config','state',next);this.sync();return next;}
  setSchedules(items){schedules(items,this.settings());this.store.put('schedules','state',items);this.sync();return items;}
  syncPayload(){const payload={config:this.settings(),schedules:this.store.get('schedules')||[]};return {...payload,version:createHash('sha256').update(JSON.stringify(payload)).digest('hex').slice(0,16),server_time:this.clock()};}
  sync(){this.transport.send('sync',this.syncPayload());}
  feed(input){
    object(input);const old=this.store.get('commands',input.command_id);
    // Retry must preserve the original payload, including its original expiry.
    if(old){
      if(!sameCommand(old,input)) throw new Invalid('COMMAND_ID_CONFLICT');
      // DELIVERY_UNKNOWN means the device may have received the first publish,
      // but its result did not reach the server. Re-send the exact same command
      // so the device can return its durable result or safely reject the expiry.
      if(old.status==='DELIVERY_UNKNOWN'){
        const {command_id,source,target_portion_g,created_at,expires_at,override,retry_of}=old;
        const payload={command_id,source,target_portion_g,created_at,expires_at,override,
          ...(retry_of===undefined?{}:{retry_of})};
        for(const key of ['pet_id','recognition_id','recognition_expires_at','recognition_source','confidence'])if(old[key]!==undefined)payload[key]=old[key];
        return {...old,delivery_attempted:this.transport.send('command',payload)};
      }
      return old;
    }
    const c={...command(input,this.settings(),this.clock())};
    for(const key of ['pet_id','recognition_id','recognition_expires_at','recognition_source','confidence'])delete c[key];
    if(c.retry_of){
      const parent=this.store.get('commands',c.retry_of);
      if(!parent||!['PARTIAL','JAM_ERROR','TIMEOUT'].includes(parent.status)||typeof parent.actual_weight_g!=='number'||
        Math.abs(parent.target_portion_g-parent.actual_weight_g-c.target_portion_g)>0.01)throw new Invalid('INVALID_REMAINDER');
      if(this.store.all('commands').some(x=>x.retry_of===c.retry_of&&!['REJECTED','COMMAND_EXPIRED'].includes(x.status)))throw new Invalid('REMAINDER_ALREADY_REQUESTED');
    }
    const cfg=this.settings(),state=this.state();
    let reason=cfg.lockdown?'SAFETY_LOCKOUT':cfg.require_pet&&!this.identityValid()?'UNKNOWN_PET':!cfg.food_confirmed?'UNVERIFIED':null;
    if(!reason && state.connection==='OFFLINE') reason='OFFLINE';
    if(!reason&&state.device?.locked===true)reason='RECONCILIATION_REQUIRED';
    const previous=[...this.store.all('commands'),...this.store.all('legacy_history').map(r=>({...r,occurred_at:Date.parse(r.timestamp)/1000}))]
      .filter(r=>dispensedStatuses.has(r.status)).sort((a,b)=>b.occurred_at-a.occurred_at)[0];
    if(!reason&&previous&&this.clock()-previous.occurred_at<cfg.min_interval_s)reason='COOLDOWN';
    if(!reason&&state.daily.actual_dispensed_g+c.target_portion_g>cfg.daily_limit_g)reason='DAILY_LIMIT';
    if(!reason&&state.daily.confirmed_sessions>=cfg.max_daily_feeds)reason='DAILY_FEED_LIMIT';
    if(!reason&&typeof state.device?.weight_g==='number'&&state.device.weight_g+c.target_portion_g>cfg.bowl_capacity_g)reason='BOWL_FULL';
    if(!reason&&typeof state.device?.distance_cm==='number'&&state.device.distance_cm>=cfg.empty_threshold_cm)reason='FOOD_EMPTY';
    if(cfg.require_pet&&!reason){const p=this.identity;Object.assign(c,{pet_id:p.pet_id,recognition_id:p.recognition_id,
      recognition_expires_at:p.expires_at,recognition_source:p.source,confidence:p.confidence});}
    const row={...c,status:reason?'REJECTED':'QUEUED',error_code:reason,actual_weight_g:null,updated_at:this.clock(),identity_context:cfg.require_pet?this.identity:null};
    this.store.put('commands',c.command_id,row);
    if(!reason)this.transport.send('command',c);
    return this.store.get('commands',c.command_id);
  }
  heartbeat(h){
    object(h);number(h.occurred_at,0,4102444800,'occurred_at',true);
    if(typeof h.busy!=='boolean')throw new Invalid('INVALID_HEARTBEAT');
    if(h.weight_g!==null)number(h.weight_g,0,5000,'weight_g');
    const previous=this.store.get('heartbeat');
    this.store.put('heartbeat','state',{...h,received_at:this.clock()});
    // Keep device skew well below the command's 10-second future-time tolerance.
    const clockDrift=Number.isInteger(h.occurred_at)&&Math.abs(this.clock()-h.occurred_at)>3;
    const hasConfigVersion=typeof h.config_version==='string'&&h.config_version.length>0;
    if(!previous || previous.boot_id!==h.boot_id || this.clock()-previous.received_at>20 || (hasConfigVersion&&h.config_version!==this.syncPayload().version) || clockDrift)this.sync();
  }
  event(e){
    object(e);identifier(e.event_id,'event_id');identifier(e.status,'status');
    number(e.occurred_at,0,4102444800,'occurred_at',true);
    if(e.command_id!==null&&e.command_id!==undefined)identifier(e.command_id,'command_id');
    if(e.actual_weight_g!==null&&e.actual_weight_g!==undefined)number(e.actual_weight_g,0,5000,'actual_weight_g');
    if(e.target_portion_g!==undefined)number(e.target_portion_g,0,500,'target_portion_g');
    if(!Number.isInteger(e.seq)||e.seq<1)throw new Invalid('INVALID_FIELD','seq');
    return this.store.transaction(()=>{
      if(this.store.get('events',e.event_id))return {duplicate:true};
      this.store.put('events',e.event_id,e);
      if(e.command_id && (terminal.has(e.status)||['ACCEPTED','DISPENSING'].includes(e.status))){
        const old=this.store.get('commands',e.command_id);
        // Terminal state is immutable to late ACCEPTED/DISPENSING. Post-feed observations are independent events.
        if(!old || (!terminal.has(old.status) && e.seq>(old.last_seq||0))){
          this.store.put('commands',e.command_id,{...old,...e,updated_at:this.clock(),last_seq:e.seq});
        }
      }
      return {duplicate:false};
    });
  }
  state(){
    const h=this.store.get('heartbeat');
    const cfg=this.settings(), commands=this.store.all('commands'),today=dayKey(this.clock(),cfg.timezone_offset_min);
    const confirmed=[...commands,...this.store.all('legacy_history').map(r=>({...r,occurred_at:Date.parse(r.timestamp)/1000}))].filter(c=>dispensedStatuses.has(c.status)&&typeof c.actual_weight_g==='number'&&
      Number.isFinite(c.occurred_at)&&dayKey(c.occurred_at,cfg.timezone_offset_min)===today);
    return {mode:this.transport.mode,connection:!h||this.clock()-h.received_at>20?'OFFLINE':h.busy?'BUSY':'ONLINE',
      device:h,config:cfg,identity:this.identity?{...this.identity,valid:this.identityValid()}:null,schedules:this.store.get('schedules')||[],
      daily:{date:today,actual_dispensed_g:confirmed.reduce((sum,c)=>sum+c.actual_weight_g,0),confirmed_sessions:confirmed.length},
      commands:commands.slice(0,100),events:this.store.all('events').slice(0,200)};
  }
  id(){return randomUUID();}
}
