import {randomUUID,createHash} from 'node:crypto';
import {defaults,config,command,schedules,terminal,dispensedStatuses,identifier,number,object,Invalid,sameCommand,dayKey} from '../domain/feedingPolicy.mjs';
export class FeedingService {
  constructor(store, transport, clock=()=>Math.floor(Date.now()/1000)) { this.store=store;this.transport=transport;this.clock=clock; }
  settings(){return {...defaults,...this.store.get('config')};}
  configure(patch){const next=config({...this.settings(),...object(patch)});schedules(this.store.get('schedules')||[],next);this.store.put('config','state',next);this.sync();return next;}
  setSchedules(items){schedules(items,this.settings());this.store.put('schedules','state',items);this.sync();return items;}
  syncPayload(){const payload={config:this.settings(),schedules:this.store.get('schedules')||[]};return {...payload,version:createHash('sha256').update(JSON.stringify(payload)).digest('hex').slice(0,16)};}
  sync(){this.transport.send('sync',this.syncPayload());}
  feed(input){
    object(input);const old=this.store.get('commands',input.command_id);
    // Retry must preserve the original payload, including its original expiry.
    if(old){if(!sameCommand(old,input)) throw new Invalid('COMMAND_ID_CONFLICT');return old;}
    const c=command(input,this.settings(),this.clock());
    if(c.retry_of){
      const parent=this.store.get('commands',c.retry_of);
      if(!parent||!['PARTIAL','JAM_ERROR','TIMEOUT'].includes(parent.status)||typeof parent.actual_weight_g!=='number'||
        Math.abs(parent.target_portion_g-parent.actual_weight_g-c.target_portion_g)>0.01)throw new Invalid('INVALID_REMAINDER');
      if(this.store.all('commands').some(x=>x.retry_of===c.retry_of&&!['REJECTED','COMMAND_EXPIRED'].includes(x.status)))throw new Invalid('REMAINDER_ALREADY_REQUESTED');
    }
    const cfg=this.settings(),state=this.state();
    let reason=cfg.lockdown?'SAFETY_LOCKOUT':cfg.require_pet?'UNKNOWN_PET':!cfg.food_confirmed?'UNVERIFIED':null;
    if(!reason && state.connection==='OFFLINE') reason='OFFLINE';
    if(!reason&&state.device?.locked===true)reason='RECONCILIATION_REQUIRED';
    const previous=[...this.store.all('commands'),...this.store.all('legacy_history').map(r=>({...r,occurred_at:Date.parse(r.timestamp)/1000}))]
      .filter(r=>dispensedStatuses.has(r.status)).sort((a,b)=>b.occurred_at-a.occurred_at)[0];
    if(!reason&&previous&&this.clock()-previous.occurred_at<cfg.min_interval_s)reason='COOLDOWN';
    if(!reason&&state.daily.actual_dispensed_g+c.target_portion_g>cfg.daily_limit_g)reason='DAILY_LIMIT';
    if(!reason&&state.daily.confirmed_sessions>=cfg.max_daily_feeds)reason='DAILY_FEED_LIMIT';
    if(!reason&&typeof state.device?.weight_g==='number'&&state.device.weight_g+c.target_portion_g>cfg.bowl_capacity_g)reason='BOWL_FULL';
    if(!reason&&typeof state.device?.distance_cm==='number'&&state.device.distance_cm>=cfg.empty_threshold_cm)reason='FOOD_EMPTY';
    const row={...c,status:reason?'REJECTED':'QUEUED',error_code:reason,actual_weight_g:null,updated_at:this.clock()};
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
    if(!previous || previous.boot_id!==h.boot_id || this.clock()-previous.received_at>20 || h.config_version!==this.syncPayload().version)this.sync();
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
      device:h,config:cfg,schedules:this.store.get('schedules')||[],
      daily:{date:today,actual_dispensed_g:confirmed.reduce((sum,c)=>sum+c.actual_weight_g,0),confirmed_sessions:confirmed.length},
      commands:commands.slice(0,100),events:this.store.all('events').slice(0,200)};
  }
  id(){return randomUUID();}
}
