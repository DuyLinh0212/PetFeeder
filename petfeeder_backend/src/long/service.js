import {randomUUID,createHash} from 'node:crypto';
import {defaults,config,command,schedules,terminal,identifier,number,object,Invalid,sameCommand,dayKey} from './policy.js';
export class Service {
  constructor(store, transport, clock=()=>Math.floor(Date.now()/1000)) { this.store=store;this.transport=transport;this.clock=clock; }
  settings(){return this.store.get('config')||{...defaults};}
  configure(patch){const next=config({...this.settings(),...object(patch)});schedules(this.store.get('schedules')||[],next);this.store.put('config','state',next);this.sync();return next;}
  setSchedules(items){schedules(items,this.settings());this.store.put('schedules','state',items);this.sync();return items;}
  syncPayload(){const payload={config:this.settings(),schedules:this.store.get('schedules')||[]};return {...payload,version:createHash('sha256').update(JSON.stringify(payload)).digest('hex').slice(0,16)};}
  sync(){this.transport.send('sync',this.syncPayload());}
  feed(input){
    object(input);const old=this.store.get('commands',input.command_id);
    // Retry must preserve the original payload, including its original expiry.
    if(old){if(!sameCommand(old,input)) throw new Invalid('COMMAND_ID_CONFLICT');return old;}
    const c=command(input,this.settings(),this.clock());
    const cfg=this.settings(),state=this.state();
    let reason=cfg.require_pet?'UNKNOWN_PET':!cfg.food_confirmed?'UNVERIFIED':null;
    if(!reason && state.connection==='OFFLINE') reason='OFFLINE';
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
    const confirmed=commands.filter(c=>['SUCCESS','PARTIAL','OVER_PORTION'].includes(c.status)&&typeof c.actual_weight_g==='number'&&
      Number.isFinite(c.occurred_at)&&dayKey(c.occurred_at,cfg.timezone_offset_min)===today);
    return {mode:this.transport.mode,connection:!h||this.clock()-h.received_at>20?'OFFLINE':h.busy?'BUSY':'ONLINE',
      device:h,config:cfg,schedules:this.store.get('schedules')||[],
      daily:{date:today,actual_dispensed_g:confirmed.reduce((sum,c)=>sum+c.actual_weight_g,0),confirmed_sessions:confirmed.length},
      commands:commands.slice(0,100),events:this.store.all('events').slice(0,200)};
  }
  id(){return randomUUID();}
}
