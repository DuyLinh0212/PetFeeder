import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import express from 'express';
import {Storage} from '../src/long/storage.js';
import {Service} from '../src/long/service.js';
import {DeviceSimulator} from '../src/long/deviceSimulator.js';
import {createIntegration} from '../src/long/integration.mjs';

function fixture(t){
  let now=Date.parse('2026-10-19T00:00:00Z')/1000,device,n=0;
  const db=new Storage(),local=new Storage();
  const service=new Service(db,{mode:'TEST',send(kind,body){if(device?.online){if(kind==='sync')device.sync(body);else device.receive(body);}}},()=>now);
  const boot=()=>{device=new DeviceSimulator(local,e=>service.event(e),h=>service.heartbeat(h),()=>now);service.sync();device.heartbeat();};
  boot();service.configure({food_confirmed:true,food_label:'Chủ xác nhận'});
  t.after(()=>{db.close();local.close();});
  return {db,local,service,boot,get device(){return device;},
    cmd(extra={}){return {command_id:`merge-${++n}`,source:'APP',target_portion_g:20,override:false,created_at:now,expires_at:now+60,...extra};},
    step(seconds){now+=seconds;device.tick();}};
}

test('C03/N03 simultaneous sources and replay cannot start a second session',t=>{
  const f=fixture(t),c=f.cmd();f.service.feed(c);
  const first=f.device.s.active.command_id;
  f.service.feed(c);
  assert.equal(f.device.s.active.command_id,first);
  assert.equal(f.service.feed(f.cmd({source:'BUTTON'})).error_code,'BUSY');
  assert.equal(f.service.feed(f.cmd({source:'SCHEDULE'})).error_code,'BUSY');
  assert.equal(f.local.all('device_totals')[0].feeds,1);
});
test('C05/N10/N11 empty hopper, ultrasonic timeout, missing weight and unstable scale stay distinct',t=>{
  const f=fixture(t);
  f.device.sensors.distance_cm=21;
  assert.equal(f.service.feed(f.cmd()).error_code,'FOOD_EMPTY');
  f.device.sensors.distance_cm=NaN;
  assert.equal(f.service.feed(f.cmd()).error_code,'SENSOR_ERROR');
  f.device.sensors.distance_cm=5;f.device.sensors.weight_g=null;
  assert.equal(f.service.feed(f.cmd()).error_code,'SENSOR_ERROR');
  f.device.sensors.weight_g=0;f.device.sensors.stable=false;
  assert.equal(f.service.feed(f.cmd()).error_code,'SENSOR_ERROR');
  assert.equal(f.device.s.active,null);
});
test('N01 additional portion cannot overfill the bowl',t=>{
  const f=fixture(t);f.device.sensors.weight_g=140;f.device.heartbeat();
  assert.equal(f.service.feed(f.cmd()).error_code,'BOWL_FULL');
  assert.equal(f.device.s.active,null);
});
test('N02 number of sessions survives reboot and resets on next day',t=>{
  const f=fixture(t);f.service.configure({max_daily_feeds:2});
  for(let n=0;n<2;n++){f.service.feed(f.cmd());f.step(4);f.step(181);}
  f.boot();assert.equal(f.service.feed(f.cmd()).error_code,'DAILY_FEED_LIMIT');
  f.step(86400);assert.equal(f.service.feed(f.cmd()).status,'DISPENSING');
});
test('N04 partial recovery requests only the missing amount and cannot claim it twice',t=>{
  const f=fixture(t),c=f.cmd();f.device.sensors.auto_feed=false;
  f.service.feed(c);f.device.sensors.weight_g=8;f.step(1);f.device.finish('JAM_ERROR',8,'JAM_ERROR');
  f.step(181);
  assert.throws(()=>f.service.feed(f.cmd({retry_of:c.command_id,target_portion_g:20})),/INVALID_REMAINDER/);
  const remainder=f.cmd({retry_of:c.command_id,target_portion_g:12});
  assert.equal(f.service.feed(remainder).status,'DISPENSING');
  assert.equal(f.service.feed(remainder).command_id,remainder.command_id);
  assert.throws(()=>f.service.feed(f.cmd({retry_of:c.command_id,target_portion_g:12})),/REMAINDER_ALREADY_REQUESTED/);
  f.device.sensors.auto_feed=true;f.step(3);
  assert.equal(f.db.get('commands',remainder.command_id).actual_weight_g,12);
  assert.equal(f.service.state().daily.actual_dispensed_g,20);
});
test('N05/N06 pulse limit returns partial and over-portion never reports success',t=>{
  const f=fixture(t);f.service.configure({max_feed_pulses:2});
  const c=f.cmd();f.service.feed(c);f.step(2);
  assert.equal(f.db.get('commands',c.command_id).status,'PARTIAL');
  assert.equal(f.db.get('commands',c.command_id).actual_weight_g,10);
  f.step(181);f.service.configure({max_feed_pulses:15});
  const next=f.cmd();f.device.sensors.auto_feed=false;f.service.feed(next);
  f.device.sensors.weight_g+=25;f.step(1);
  assert.equal(f.db.get('commands',next.command_id).status,'OVER_PORTION');
});
test('N07/N09 measurement interference and modeled bowl removal stop without claiming zero delivery',t=>{
  const f=fixture(t),c=f.cmd();f.device.sensors.weight_g=30;f.device.heartbeat();
  f.service.feed(c);f.device.sensors.weight_g=25;f.step(1);
  assert.equal(f.db.get('commands',c.command_id).status,'INTERRUPTED');
  assert.equal(f.db.get('commands',c.command_id).actual_weight_g,null);
  f.device.reconcile();f.step(181);const next=f.cmd();f.service.feed(next);
  f.device.sensors.bowl_present=false;f.step(1);
  assert.equal(f.db.get('commands',next.command_id).error_code,'BOWL_MISSING');
  assert.equal(f.device.s.active,null);
});
test('N12/N13/N14 jam stops and idle changes do not assert the pet ate',t=>{
  const f=fixture(t);f.device.sensors.jammed=true;
  const c=f.cmd();f.service.feed(c);f.step(3);
  assert.equal(f.db.get('commands',c.command_id).status,'JAM_ERROR');
  f.device.sensors.weight_g=20;f.step(1);
  assert(f.db.all('events').some(e=>e.status==='MANUAL_REFILL'));
  f.device.sensors.weight_g=10;f.step(1);
  assert(f.db.all('events').some(e=>e.status==='WEIGHT_DECREASED'&&e.error_code==='UNKNOWN_CAUSE'));
});
test('C07/C08 safety lock stops an active session and cannot be overridden',t=>{
  const f=fixture(t),c=f.cmd();f.service.feed(c);f.service.configure({lockdown:true});f.step(1);
  assert.equal(f.db.get('commands',c.command_id).status,'INTERRUPTED');
  assert.throws(()=>f.service.feed(f.cmd({override:true})),/OVERRIDE_NOT_SUPPORTED/);
  assert.equal(f.service.feed(f.cmd()).error_code,'SAFETY_LOCKOUT');
});
test('N21 ten schedules remain supported and an eleventh is rejected without truncation',t=>{
  const f=fixture(t),rows=Array.from({length:10},(_,n)=>({schedule_id:`s${n}`,hour:7,minute:n,target_portion_g:20,days:[1],enabled:true}));
  f.service.setSchedules(rows);assert.equal(f.device.s.schedules.length,10);
  assert.throws(()=>f.service.setSchedules([...rows,{...rows[0],schedule_id:'eleventh'}]));
  assert.equal(f.service.state().schedules.length,10);
});
test('JSON migration preserves records, settings, read state and source bytes across restarts',async t=>{
  const dir=mkdtempSync(join(tmpdir(),'petfeeder-migration-')),file=join(dir,'database.json');
  const old={device_config:{safe_interval_sec:240,pulse_step_ms:650},
    schedules:[{id:'old-schedule',name:'Bữa cũ',time:'07:30',portion_g:20,days:['T2'],enabled:true}],
    feeding_history:[{id:'old-feed',timestamp:'2026-10-19T00:00:00Z',status:'SUCCESS',actual_weight_g:19,target_portion_g:20,trigger_source:'button'}],
    alerts:[{id:'old-alert',timestamp:'2026-10-19T00:01:00Z',title:'Cảnh báo cũ',message:'Giữ nguyên',read:true,level:'info'}]};
  const bytes=JSON.stringify(old);writeFileSync(file,bytes);
  let integration=createIntegration({dataDir:dir,legacyFile:file,transport:{mode:'TEST',send(){return true;}}});
  assert.equal(integration.service.settings().min_interval_s,240);
  assert.equal(integration.service.settings().pulse_step_ms,650);
  const app=express();app.use(express.json());app.use('/api',integration.router);
  const server=app.listen(0,'127.0.0.1');await once(server,'listening');
  const base=`http://127.0.0.1:${server.address().port}/api`;
  try{
    assert.equal((await (await fetch(base+'/feeding/history')).json()).data[0].id,'old-feed');
    assert.equal((await (await fetch(base+'/notifications')).json()).data[0].read,true);
    await fetch(base+'/feeding/history',{method:'DELETE'});
    assert.equal((await (await fetch(base+'/feeding/history')).json()).data.length,0);
    assert.equal(integration.db.all('legacy_history').length,1);
  }finally{await new Promise(r=>server.close(r));integration.close();}
  integration=createIntegration({dataDir:dir,legacyFile:file,transport:{mode:'TEST',send(){return true;}}});
  try{
    assert.equal(integration.db.all('legacy_history').length,1);
    assert.equal(integration.service.state().schedules[0].schedule_id,'old-schedule');
    assert.equal(integration.db.get('hidden_history').length,1);
    assert.equal(readFileSync(file,'utf8'),bytes);
  }finally{integration.close();assert(dir.startsWith(join(tmpdir(),'petfeeder-migration-')));rmSync(dir,{recursive:true,force:true});}
});
test('invalid legacy schedules abort migration without replacing the source or committing partial imports',()=>{
  const dir=mkdtempSync(join(tmpdir(),'petfeeder-migration-')),file=join(dir,'database.json');
  const bytes=JSON.stringify({device_config:{safe_interval_sec:240},schedules:[{id:'bad',name:'Lịch lỗi',time:'25:00',portion_g:20,days:['T2'],enabled:true}]});
  writeFileSync(file,bytes);
  try{
    assert.throws(()=>createIntegration({dataDir:dir,legacyFile:file,transport:{mode:'TEST',send(){}}}),/INVALID_FIELD/);
    const db=new Storage(join(dir,'backend.sqlite'));
    try{assert.equal(db.get('migrations','legacy-json-v1'),null);assert.equal(db.get('config'),null);assert.equal(db.get('schedules'),null);}
    finally{db.close();}
    assert.equal(readFileSync(file,'utf8'),bytes);
  }finally{assert(dir.startsWith(join(tmpdir(),'petfeeder-migration-')));rmSync(dir,{recursive:true,force:true});}
});
