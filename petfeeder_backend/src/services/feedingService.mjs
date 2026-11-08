import {randomUUID,createHash} from 'node:crypto';
import {defaults,config,command,schedules,terminal,dispensedStatuses,identifier,number,object,Invalid,sameCommand,dayKey} from '../domain/feedingPolicy.mjs';

const commandFields=['command_id','source','target_portion_g','created_at','expires_at'];

function wireCommand(row){
  return Object.fromEntries(commandFields.filter(key=>row[key]!==undefined).map(key=>[key,row[key]]));
}

export class FeedingService {
  constructor(store,transport,clock=()=>Math.floor(Date.now()/1000)) {
    this.store=store;
    this.transport=transport;
    this.clock=clock;
    this.lastHeartbeatSync=null;
  }

  async settings(){
    const saved=await this.store.get('config')||{};
    return Object.fromEntries(Object.keys(defaults).map(key=>[key,saved[key]??defaults[key]]));
  }

  async configure(patch){
    const next=config({...await this.settings(),...object(patch)});
    schedules(await this.store.get('schedules')||[],next);
    await this.store.put('config','state',next);
    await this.sync();
    return next;
  }

  async setSchedules(items){
    schedules(items,await this.settings());
    await this.store.put('schedules','state',items);
    await this.sync();
    return items;
  }

  async syncPayload(){
    const [savedConfig,schedulesList,h]=await Promise.all([
      this.settings(),this.store.get('schedules'),this.store.get('heartbeat'),
    ]);
    const payload={config:savedConfig,schedules:schedulesList||[]};
    return {...payload,version:createHash('sha256').update(JSON.stringify(payload)).digest('hex').slice(0,16),
      server_time:this.clock(),previous_device_seen_at:h?.previous_device_seen_at??h?.received_at??null};
  }

  async sync(){
    return this.transport.send('sync',await this.syncPayload());
  }

  async feed(input){
    object(input);
    const old=await this.store.get('commands',input.command_id);
    if(old){
      if(!sameCommand(old,input))throw new Invalid('COMMAND_ID_CONFLICT');
      return old;
    }
    const cfg=await this.settings();
    const c=command(input,cfg,this.clock());
    const state=await this.state();
    let reason=state.connection==='OFFLINE'?'OFFLINE':null;
    if(!reason&&state.device?.locked===true)reason='RECONCILIATION_REQUIRED';
    const [commandRows,legacyRows]=await Promise.all([
      this.store.all('commands'),this.store.all('legacy_history'),
    ]);
    const previous=[...commandRows,...legacyRows.map(r=>({...r,occurred_at:Date.parse(r.timestamp)/1000}))]
      .filter(r=>dispensedStatuses.has(r.status)).sort((a,b)=>b.occurred_at-a.occurred_at)[0];
    if(!reason&&previous&&this.clock()-previous.occurred_at<cfg.min_interval_s)reason='COOLDOWN';
    if(!reason&&state.daily.actual_dispensed_g+c.target_portion_g>cfg.daily_limit_g)reason='DAILY_LIMIT';
    if(!reason&&state.daily.confirmed_sessions>=cfg.max_daily_feeds)reason='DAILY_FEED_LIMIT';
    if(!reason&&typeof state.device?.weight_g==='number'&&state.device.weight_g+c.target_portion_g>cfg.bowl_capacity_g)reason='BOWL_FULL';
    const row={...c,status:reason?'REJECTED':'QUEUED',error_code:reason,actual_weight_g:null,updated_at:this.clock()};
    await this.store.put('commands',c.command_id,row);
    if(!reason){
      const sent=await this.transport.send('command',wireCommand(row));
      if(sent!==false)await this.store.markCommandPublished?.(c.command_id);
      const current=await this.store.get('commands',c.command_id);
      if(sent===false&&current?.status==='QUEUED'){
        await this.store.put('commands',c.command_id,{
          ...current,status:'DELIVERY_FAILED',error_code:'MQTT_UNAVAILABLE',updated_at:this.clock(),
        });
      }
    }
    return await this.store.get('commands',c.command_id);
  }

  async heartbeat(h){
    object(h);number(h.occurred_at,0,4102444800,'occurred_at',true);
    if(typeof h.busy!=='boolean')throw new Invalid('INVALID_HEARTBEAT');
    if(h.weight_g!==null)number(h.weight_g,0,5000,'weight_g');
    const previous=await this.store.get('heartbeat');
    const previousDeviceSeenAt=previous?.boot_id===h.boot_id
      ?previous?.previous_device_seen_at??previous?.received_at??null
      :previous?.received_at??null;
    await this.store.put('heartbeat','state',{...h,previous_device_seen_at:previousDeviceSeenAt,received_at:this.clock()});
    const clockDrift=Number.isInteger(h.occurred_at)&&Math.abs(this.clock()-h.occurred_at)>3;
    const hasConfigVersion=typeof h.config_version==='string'&&h.config_version.length>0;
    const version=(await this.syncPayload()).version,now=this.clock();
    const configMismatch=hasConfigVersion&&h.config_version!==version;
    const recoveredFromBusy=previous?.busy&&!h.busy&&configMismatch;
    const newClockDrift=clockDrift&&previous&&previous.boot_id===h.boot_id&&Math.abs(previous.received_at-previous.occurred_at)<=3;
    if(!previous||previous.boot_id!==h.boot_id||this.clock()-previous.received_at>20||configMismatch||clockDrift){
      const last=this.lastHeartbeatSync;
      if(!recoveredFromBusy&&!newClockDrift&&last?.version===version&&now>=last.at&&now-last.at<15)return;
      if(await this.sync()!==false)this.lastHeartbeatSync={version,at:now};
    }
  }

  async event(e){
    object(e);identifier(e.event_id,'event_id');identifier(e.status,'status');
    number(e.occurred_at,0,4102444800,'occurred_at',true);
    if(e.command_id!==null&&e.command_id!==undefined)identifier(e.command_id,'command_id');
    if(e.actual_weight_g!==null&&e.actual_weight_g!==undefined)number(e.actual_weight_g,0,5000,'actual_weight_g');
    if(e.target_portion_g!==undefined)number(e.target_portion_g,0,500,'target_portion_g');
    if(!Number.isInteger(e.seq)||e.seq<1)throw new Invalid('INVALID_FIELD','seq');
    return this.store.transaction(async()=>{
      const inserted=this.store.putIfAbsent
        ?await this.store.putIfAbsent('events',e.event_id,e)
        :!(await this.store.get('events',e.event_id))&&(await this.store.put('events',e.event_id,e),true);
      if(!inserted)return {duplicate:true};
      if(e.command_id&&(terminal.has(e.status)||['ACCEPTED','DISPENSING'].includes(e.status))){
        const old=await this.store.get('commands',e.command_id);
        if(!old||(!terminal.has(old.status)&&e.seq>(old.last_seq||0))){
          await this.store.put('commands',e.command_id,{...old,...e,updated_at:this.clock(),last_seq:e.seq});
        }
      }
      return {duplicate:false};
    });
  }

  async state(){
    const [h,savedConfig,schedulesList,commands,events,legacyRows]=await Promise.all([
      this.store.get('heartbeat'),this.settings(),this.store.get('schedules'),this.store.all('commands'),
      this.store.all('events'),this.store.all('legacy_history'),
    ]);
    const today=dayKey(this.clock(),savedConfig.timezone_offset_min);
    const confirmed=[...commands,...legacyRows.map(r=>({...r,occurred_at:Date.parse(r.timestamp)/1000}))]
      .filter(c=>dispensedStatuses.has(c.status)&&typeof c.actual_weight_g==='number'&&Number.isFinite(c.occurred_at)&&dayKey(c.occurred_at,savedConfig.timezone_offset_min)===today);
    return {
      mode:this.transport.mode,
      connection:!h||this.clock()-h.received_at>20?'OFFLINE':h.busy?'BUSY':'ONLINE',
      device:h,config:savedConfig,schedules:schedulesList||[],
      daily:{date:today,actual_dispensed_g:confirmed.reduce((sum,c)=>sum+c.actual_weight_g,0),confirmed_sessions:confirmed.length},
      commands:commands.slice(0,100),events:events.slice(0,200),
    };
  }

  id(){return randomUUID();}
}
