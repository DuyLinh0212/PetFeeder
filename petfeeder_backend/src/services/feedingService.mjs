import {randomUUID,createHash} from 'node:crypto';
import {defaults,config,command,schedules,terminal,dispensedStatuses,identifier,number,object,Invalid,sameCommand,dayKey} from '../domain/feedingPolicy.mjs';

const commandFields=['command_id','source','target_portion_g','created_at','expires_at','pet_id','recognition_id','recognition_expires_at','recognition_source','confidence'];

function wireCommand(row){
  return Object.fromEntries(commandFields.filter(key=>row[key]!==undefined).map(key=>[key,row[key]]));
}

export class FeedingService {
  constructor(store, transport, clock=()=>Math.floor(Date.now()/1000)) { this.store=store;this.transport=transport;this.clock=clock;this.lastHeartbeatSync=null;this.identity=null; }
  settings(){
    const saved=this.store.get('config')||{};
    return Object.fromEntries(Object.keys(defaults).map(key=>[key,saved[key]??defaults[key]]));
  }
  configure(patch){const next=config({...this.settings(),...object(patch)});schedules(this.store.get('schedules')||[],next);this.store.put('config','state',next);this.sync();return next;}
  setSchedules(items){schedules(items,this.settings());this.store.put('schedules','state',items);this.sync();return items;}
  syncPayload(){const payload={config:this.settings(),schedules:this.store.get('schedules')||[]};return {...payload,version:createHash('sha256').update(JSON.stringify(payload)).digest('hex').slice(0,16),server_time:this.clock()};}
  sync(){return this.transport.send('sync',this.syncPayload());}
  observePet(detections,{issuedAt=this.clock(),confirmed=true,active=true}={}){
    const boxes=detections.filter(b=>['cat','dog'].includes(b.label)&&typeof b.confidence==='number'&&Number.isFinite(b.confidence)&&b.confidence>=0.5&&b.confidence<=1);
    const best=boxes.sort((a,b)=>b.confidence-a.confidence)[0],now=this.clock();
    const matched=!!best&&confirmed&&now-issuedAt<3;
    this.identity={recognition_id:this.id(),pet_id:best?`species-${best.label}`:'unknown',pet_type:best?.label||null,
      camera_active:active,matched,confidence:best?.confidence||0,confidence_kind:'MODEL',source:'YOLO_PET_PRESENCE',issued_at:issuedAt,expires_at:issuedAt+5};
    this.transport.send('identity',this.identity);return this.identity;
  }
  revokePet(){return this.observePet([],{confirmed:false,active:false});}
  identityValid(){const p=this.identity;return !!p&&p.camera_active&&p.matched&&p.source==='YOLO_PET_PRESENCE'&&
    ['cat','dog'].includes(p.pet_type)&&p.confidence>=0.5&&p.issued_at<=this.clock()+2&&p.expires_at>this.clock()&&p.expires_at-p.issued_at<=5;}
  feed(input){
    object(input);const old=this.store.get('commands',input.command_id);
    // A repeated ID is idempotent: return its recorded state without publishing again.
    if(old){
      if(!sameCommand(old,input)) throw new Invalid('COMMAND_ID_CONFLICT');
      return old;
    }
    const c=command(input,this.settings(),this.clock());
    const cfg=this.settings(),state=this.state();
    let reason=cfg.require_pet&&!this.identityValid()?'UNKNOWN_PET':null;
    if(!reason && state.connection==='OFFLINE') reason='OFFLINE';
    if(!reason&&state.device?.locked===true)reason='RECONCILIATION_REQUIRED';
    const previous=[...this.store.all('commands'),...this.store.all('legacy_history').map(r=>({...r,occurred_at:Date.parse(r.timestamp)/1000}))]
      .filter(r=>dispensedStatuses.has(r.status)).sort((a,b)=>b.occurred_at-a.occurred_at)[0];
    if(!reason&&previous&&this.clock()-previous.occurred_at<cfg.min_interval_s)reason='COOLDOWN';
    if(!reason&&state.daily.actual_dispensed_g+c.target_portion_g>cfg.daily_limit_g)reason='DAILY_LIMIT';
    if(!reason&&state.daily.confirmed_sessions>=cfg.max_daily_feeds)reason='DAILY_FEED_LIMIT';
    if(!reason&&typeof state.device?.weight_g==='number'&&state.device.weight_g+c.target_portion_g>cfg.bowl_capacity_g)reason='BOWL_FULL';
    if(cfg.require_pet&&!reason){const p=this.identity;Object.assign(c,{pet_id:p.pet_id,recognition_id:p.recognition_id,
      recognition_expires_at:p.expires_at,recognition_source:p.source,confidence:p.confidence});}
    const row={...c,status:reason?'REJECTED':'QUEUED',error_code:reason,actual_weight_g:null,updated_at:this.clock(),identity_context:cfg.require_pet?this.identity:null};
    this.store.put('commands',c.command_id,row);
    if(!reason){
      const sent=this.transport.send('command',wireCommand(row));
      const current=this.store.get('commands',c.command_id);
      if(!sent&&current?.status==='QUEUED')this.store.put('commands',c.command_id,{
        ...current,status:'DELIVERY_FAILED',error_code:'MQTT_UNAVAILABLE',updated_at:this.clock(),
      });
    }
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
    const version=this.syncPayload().version,now=this.clock();
    const configMismatch=hasConfigVersion&&h.config_version!==version;
    const recoveredFromBusy=previous?.busy&&!h.busy&&configMismatch;
    const newClockDrift=clockDrift&&previous&&previous.boot_id===h.boot_id&&Math.abs(previous.received_at-previous.occurred_at)<=3;
    if(!previous || previous.boot_id!==h.boot_id || this.clock()-previous.received_at>20 || configMismatch || clockDrift){
      // Throttle heartbeat retries, while new config, a new clock error and
      // completion of dispensing can still trigger their first correction immediately.
      const last=this.lastHeartbeatSync;
      if(!recoveredFromBusy&&!newClockDrift&&last?.version===version&&now>=last.at&&now-last.at<15)return;
      if(this.sync()!==false)this.lastHeartbeatSync={version,at:now};
    }
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
        // Terminal state is immutable to late ACCEPTED/DISPENSING events.
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
