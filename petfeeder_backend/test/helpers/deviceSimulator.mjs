// Device model for deterministic API/integration tests. It does not simulate ESP32 electrical timing.
import {defaults, config, schedules, command, dayKey, Invalid, sameCommand} from '../../src/domain/feedingPolicy.mjs';
import {randomUUID} from 'node:crypto';
export class DeviceSimulator {
  constructor(store, emit, heartbeat, clock=()=>Math.floor(Date.now()/1000)) {
    this.store=store;this.emitToBackend=emit;this.sendHeartbeat=heartbeat;this.clock=clock;
    this.s=store.get('device')||{config:{...defaults},schedules:[],seq:0,queue:[],active:null,
      last_end:0,scan:0,locked:false,food_since:null,stale_alert:false,observations:[]};
    this.online=true;this.bootId=randomUUID();this.sensors={weight_g:0,calibrated:true,time_valid:true,auto_feed:true,
      distance_cm:5,stable:true,bowl_present:true,jammed:false};this.lastTick=this.clock();
    if(this.s.active){const a=this.s.active;this.s.active=null;this.s.locked=true;
      this.result(a,'INTERRUPTED',null,'RECONCILIATION_REQUIRED');}
    this.save();
  }
  save(){this.store.put('device','state',this.s);}
  event(status,fields={}){
    const e={event_id:`sim-${++this.s.seq}`,seq:this.s.seq,occurred_at:this.clock(),status,...fields};
    this.s.queue.push(e);this.save();if(!this.deferring)this.flush();return e;
  }
  flush(){if(!this.online)return;while(this.s.queue.length){this.emitToBackend(this.s.queue[0]);this.s.queue.shift();this.save();}}
  sync(payload){const cfg=config(payload.config);schedules(payload.schedules,cfg);
    if(this.s.active){if(cfg.lockdown){this.s.config.lockdown=true;this.save();}return;}
    this.s.config=cfg;this.s.schedules=payload.schedules;this.s.config_version=payload.version;this.save();}
  heartbeat(){if(this.online)this.sendHeartbeat({occurred_at:this.clock(),busy:!!this.s.active,
    weight_g:this.sensors.weight_g,time_valid:this.sensors.time_valid,locked:this.s.locked,mode:'DEMO',boot_id:this.bootId,
    food_since:this.s.food_since,outbox:this.s.queue.length,config_version:this.s.config_version});}
  result(c,status,actual,error=null){const e=this.event(status,{command_id:c.command_id,
    source:c.source,target_portion_g:c.target_portion_g,actual_weight_g:actual,error_code:error});
    this.store.put('device_commands',c.command_id,{...c,...e});return e;}
  receive(c){
    const old=this.store.get('device_commands',c?.command_id);
    if(old){if(!sameCommand(old,c))throw new Invalid('COMMAND_ID_CONFLICT');if(this.online)this.emitToBackend(old);return old;}
    let reason;
    try{command(c,this.s.config,this.clock(),false);}catch(e){throw e;}
    const cfg=this.s.config,now=this.clock();
    const day=dayKey(now,cfg.timezone_offset_min);
    const total=this.store.get('device_totals',day)||{reserved_g:0,feeds:0};
    if(!this.sensors.time_valid)reason='TIME_INVALID';
    else if(now<c.created_at-10)reason='TIME_INVALID';
    else if(now>=c.expires_at)reason='COMMAND_EXPIRED';
    else if(this.s.locked)reason='RECONCILIATION_REQUIRED';
    else if(this.s.active)reason='BUSY';
    else if(cfg.lockdown)reason='SAFETY_LOCKOUT';
    else if(cfg.require_pet)reason='UNKNOWN_PET';
    else if(!cfg.food_confirmed)reason='UNVERIFIED';
    else if(!this.sensors.bowl_present)reason='BOWL_MISSING';
    else if(!this.sensors.calibrated || this.sensors.weight_g===null || !this.sensors.stable)reason='SENSOR_ERROR';
    else if(now-this.s.last_end<cfg.min_interval_s)reason='COOLDOWN';
    else if(total.reserved_g+c.target_portion_g>cfg.daily_limit_g)reason='DAILY_LIMIT';
    else if((total.feeds||0)>=cfg.max_daily_feeds)reason='DAILY_FEED_LIMIT';
    else if(this.sensors.weight_g+c.target_portion_g>cfg.bowl_capacity_g)reason='BOWL_FULL';
    else if(!Number.isFinite(this.sensors.distance_cm))reason='SENSOR_ERROR';
    else if(this.sensors.distance_cm>=cfg.empty_threshold_cm)reason='FOOD_EMPTY';
    if(!reason&&c.retry_of){
      const parent=this.store.get('device_commands',c.retry_of);
      if(!parent||!['PARTIAL','JAM_ERROR','TIMEOUT'].includes(parent.status)||typeof parent.actual_weight_g!=='number'||
        Math.abs(parent.target_portion_g-parent.actual_weight_g-c.target_portion_g)>0.01)reason='INVALID_REMAINDER';
      else if(this.store.all('device_commands').some(x=>x.retry_of===c.retry_of&&!['REJECTED','COMMAND_EXPIRED'].includes(x.status)))reason='REMAINDER_ALREADY_REQUESTED';
    }
    if(reason)return this.result(c,reason==='COMMAND_EXPIRED'?reason:'REJECTED',0,reason);
    // Reserve target and persist active session before actuator may move.
    const a={...c,baseline:this.sensors.weight_g,previous_weight:this.sensors.weight_g,started:now,day,actual:0,pulses:0};
    this.store.transaction(()=>{this.store.put('device_totals',day,{reserved_g:total.reserved_g+c.target_portion_g,feeds:(total.feeds||0)+1});this.s.active=a;
      this.store.put('device_commands',c.command_id,{...c,status:'DISPENSING',actual_weight_g:0});this.save();});
    this.result(c,'ACCEPTED',0);return this.result(c,'DISPENSING',0);
  }
  finish(status,actual,error=null){const a=this.s.active;if(!a)return;
    this.deferring=true;
    try { this.store.transaction(()=>{
    const total=this.store.get('device_totals',a.day);
    if(actual!==null)this.store.put('device_totals',a.day,{...total,reserved_g:total.reserved_g-a.target_portion_g+actual});
    this.s.active=null;this.s.last_end=this.clock();this.s.idle_weight=this.sensors.weight_g??undefined;
    if(actual===null)this.s.locked=true;
    if(actual>0&&this.sensors.weight_g!==null)this.s.observations.push({command_id:a.command_id,
      at:this.clock(),baseline:this.sensors.weight_g});
    this.result(a,status,actual,error);this.save();
    }); } finally {this.deferring=false;}
    this.flush();
  }
  reconcile(){if(this.s.active)throw new Invalid('BUSY');this.s.locked=false;this.s.last_end=this.clock();this.save();
    return this.event('RECONCILED',{error_code:'DAILY_RESERVATION_RETAINED'});}
  scanSchedules(){
    if(!this.sensors.time_valid||this.s.active)return;
    const now=this.clock(),cfg=this.s.config;
    const since=this.s.scan||now-60;
    if(now<since)return; // never replay on backward clock
    const first=Math.floor(Math.max(since,now-7*86400)/86400)*86400;
    for(let utc=first-86400;utc<=now+86400;utc+=86400){
      const date=dayKey(utc,cfg.timezone_offset_min),midnight=Date.parse(date+'T00:00:00Z')/1000-cfg.timezone_offset_min*60;
      const dow=new Date((midnight+cfg.timezone_offset_min*60)*1000).getUTCDay();
      for(const sch of this.s.schedules){
        if(!sch.enabled||!sch.days.includes(dow))continue;
        const due=midnight+sch.hour*3600+sch.minute*60,key=sch.schedule_id+':'+date;
        if(due<=since||due>now||this.store.get('device_schedule_runs',key))continue;
        this.store.put('device_schedule_runs',key,{at:now}); // before receive, survives resync/reboot
        if(now-due>=60){this.event('MISSED_SCHEDULE',{schedule_id:sch.schedule_id,date});continue;}
        this.receive({command_id:'sch:'+key,source:'SCHEDULE',target_portion_g:sch.target_portion_g,
          created_at:now,expires_at:now+cfg.command_ttl_s,override:false});
      }
    }
    this.s.scan=now;this.save();
  }
  tick(){
    const now=this.clock(),elapsed=Math.max(0,now-this.lastTick);this.lastTick=now;
    const a=this.s.active,cfg=this.s.config;
    if(a){
      if(cfg.lockdown)this.finish('INTERRUPTED',null,'SAFETY_LOCKOUT');
      else if(!this.sensors.bowl_present)this.finish('SENSOR_ERROR',null,'BOWL_MISSING');
      else if(this.sensors.weight_g===null)this.finish('SENSOR_ERROR',null,'MEASUREMENT_LOST');
      else if(!this.sensors.stable)this.finish('SENSOR_ERROR',null,'WEIGHT_UNSTABLE');
      else if(this.sensors.weight_g<a.previous_weight-2)this.finish('INTERRUPTED',null,'INTERRUPTED_PET_FEEDING');
      else{
        if(this.sensors.auto_feed&&!this.sensors.jammed)this.sensors.weight_g+=Math.min(5*elapsed,Math.max(0,a.target_portion_g-a.actual));
        a.pulses+=elapsed;a.previous_weight=this.sensors.weight_g;
        const actual=Math.max(0,this.sensors.weight_g-a.baseline);a.actual=actual;
        if(actual>a.target_portion_g+cfg.tolerance_g)this.finish('OVER_PORTION',actual,'OVER_PORTION');
        else if(actual>0&&actual>=a.target_portion_g-cfg.tolerance_g)this.finish('SUCCESS',actual);
        else if(!Number.isFinite(this.sensors.distance_cm))this.finish('SENSOR_ERROR',actual,'ULTRASONIC_TIMEOUT');
        else if(this.sensors.distance_cm>=cfg.empty_threshold_cm)this.finish(actual>0?'PARTIAL':'FOOD_EMPTY',actual,'FOOD_EMPTY');
        else if(this.sensors.jammed&&a.pulses>=cfg.anti_jam_max_retries)this.finish('JAM_ERROR',actual,'JAM_ERROR');
        else if(a.pulses>=cfg.max_feed_pulses)this.finish(actual>0?'PARTIAL':'TIMEOUT',actual,'MAX_PULSES_REACHED');
        else if(now-a.started>=cfg.feed_timeout_s)this.finish(actual>0?'PARTIAL':'TIMEOUT',actual,'FEED_TIMEOUT');
      }
    }
    const w=this.sensors.weight_g;
    if(!this.s.active&&w!==null){
      if(this.s.idle_weight!==undefined&&Math.abs(w-this.s.idle_weight)>5)
        this.event(w>this.s.idle_weight?'MANUAL_REFILL':'WEIGHT_DECREASED',{delta_g:w-this.s.idle_weight,current_bowl_weight_g:w,error_code:w>this.s.idle_weight?'OWNER_REFILL':'UNKNOWN_CAUSE'});
      if(this.s.idle_weight===undefined||Math.abs(w-this.s.idle_weight)>5)this.s.idle_weight=w;
    }
    if(w!==null){
      if(w>1&&this.s.food_since===null){this.s.food_since=now;this.s.stale_alert=false;}
      if(w<=1){this.s.food_since=null;this.s.stale_alert=false;}
      if(this.s.food_since!==null&&!this.s.stale_alert&&now-this.s.food_since>=cfg.food_stale_s){
        this.s.stale_alert=true;this.event('FOOD_STALE');
      }
    }
    for(const o of [...this.s.observations])if(now-o.at>=cfg.observation_s){
      this.event(w===null?'UNKNOWN':w<o.baseline-cfg.tolerance_g?'WEIGHT_DECREASED':'FOOD_LEFT',
        {command_id:o.command_id,weight_g:w,error_code:w===null?'SENSOR_ERROR':w<o.baseline-cfg.tolerance_g?'UNKNOWN_CAUSE':null});
      this.s.observations=this.s.observations.filter(x=>x!==o);
    }
    this.scanSchedules();this.save();this.flush();this.heartbeat();
  }
}
