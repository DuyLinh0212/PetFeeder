import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,rmSync} from 'node:fs';
import {join,resolve,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {Storage} from '../src/long/storage.js';
import {Service} from '../src/long/service.js';
import {DeviceSimulator} from '../src/long/deviceSimulator.js';
import {defaults,config,schedules,command} from '../src/long/policy.js';
function fixture(){
  let now=Date.parse('2026-10-19T00:00:00Z')/1000; // Monday 07:00 UTC+7
  const backend=new Storage(),storage=new Storage();let device;
  const service=new Service(backend,{mode:'DEMO',send(kind,p){if(device?.online){if(kind==='sync')device.sync(p);else device.receive(p);}}},()=>now);
  const boot=()=>{device=new DeviceSimulator(storage,e=>service.event(e),h=>service.heartbeat(h),()=>now);service.sync();device.heartbeat();return device;};
  boot();service.configure({food_confirmed:true,food_label:'Demo owner confirmation'});
  let next=0;
  return {service,backend,storage,boot,get device(){return device;},get now(){return now;},
    cmd(extra={}){return {command_id:`cmd-${++next}`,source:'APP',target_portion_g:20,override:false,created_at:now,expires_at:now+60,...extra};},
    step(sec){now+=sec;device.tick();},events(){return backend.all('events');}};
}
test('C01 identity policy refuses unknown pet without claiming hardware recognition',()=>{
  const f=fixture();f.service.configure({require_pet:true});
  assert.equal(f.service.feed(f.cmd()).error_code,'UNKNOWN_PET');assert.equal(f.device.s.active,null);
});
test('C02 limits include reservations and cooldown, not just acknowledged requests',()=>{
  const f=fixture();f.service.configure({daily_limit_g:30,max_portion_g:30});
  f.service.feed(f.cmd());f.step(4);assert.equal(f.device.s.active,null);
  assert.equal(f.service.feed(f.cmd()).error_code,'COOLDOWN');f.step(181);
  assert.equal(f.service.feed(f.cmd()).error_code,'DAILY_LIMIT');
});
test('C04 records FOOD_LEFT and WEIGHT_DECREASED as independent observations',()=>{
  const f=fixture();f.service.feed(f.cmd());f.step(4);f.step(61);
  assert(f.events().some(e=>e.status==='FOOD_LEFT'));
  f.step(181);const c=f.cmd();f.service.feed(c);f.step(4);f.device.sensors.weight_g-=5;f.step(61);
  assert(f.events().some(e=>e.status==='WEIGHT_DECREASED'&&e.error_code==='UNKNOWN_CAUSE'));
  assert.equal(f.backend.get('commands',c.command_id).status,'SUCCESS');
});
test('C06 food owner confirmation is required, without sensor classification',()=>{
  const f=fixture();f.service.configure({food_confirmed:false});
  assert.equal(f.service.feed(f.cmd()).error_code,'UNVERIFIED');
  assert.throws(()=>f.service.configure({food_confirmed:true,food_label:''}));
});
test('N15 one stale alert per continuous food presence; clearing bowl resets it',()=>{
  const f=fixture();f.service.configure({food_stale_s:5});f.device.sensors.weight_g=20;f.step(1);f.step(6);f.step(10);
  assert.equal(f.events().filter(e=>e.status==='FOOD_STALE').length,1);
  f.device.sensors.weight_g=0;f.step(1);f.device.sensors.weight_g=20;f.step(1);f.step(6);
  assert.equal(f.events().filter(e=>e.status==='FOOD_STALE').length,2);
});
test('N16 completed command and cooldown survive device reboot',()=>{
  const f=fixture(),c=f.cmd();f.service.feed(c);f.step(4);f.boot();
  assert.equal(f.device.receive(c).status,'SUCCESS');
  assert.equal(f.service.feed(f.cmd()).error_code,'COOLDOWN');
});
test('N17 interrupted session blocks further feed and retains conservative reservation',()=>{
  const f=fixture(),c=f.cmd();f.service.feed(c);f.step(1);f.boot();
  assert.equal(f.backend.get('commands',c.command_id).status,'INTERRUPTED');
  assert.equal(f.backend.get('commands',c.command_id).actual_weight_g,null);
  assert.equal(f.service.feed(f.cmd()).error_code,'RECONCILIATION_REQUIRED');
  assert.equal(f.storage.all('device_totals')[0].reserved_g,20);
});
test('N18 boot logic never issues a tare; sensor sample remains an external input',()=>{
  const f=fixture();f.device.sensors.weight_g=30;const sensors={...f.device.sensors};f.boot();f.device.sensors=sensors;f.device.heartbeat();
  assert.equal(f.service.state().device.weight_g,30);
  // This model assertion is not a test of physical calibration; firmware needs a hardware test.
});
function schedule(f,minute=1,days=[1]){f.service.setSchedules([{schedule_id:'breakfast',hour:7,minute,days,target_portion_g:20,enabled:true}]);f.device.tick();}
test('N19 offline schedule runs once and outbox replays after network returns',()=>{
  const f=fixture();schedule(f);f.device.online=false;f.step(60);assert(f.device.s.active);f.step(4);
  assert(f.device.s.queue.length>=3);f.device.online=true;f.device.flush();
  assert.equal(f.events().filter(e=>e.status==='SUCCESS').length,1);assert.equal(f.device.s.queue.length,0);
});
test('N20 invalid time blocks both scheduled and direct commands',()=>{
  const f=fixture();schedule(f);f.device.sensors.time_valid=false;f.step(60);assert.equal(f.device.s.active,null);
  assert.equal(f.device.receive(f.cmd()).error_code,'TIME_INVALID');
});
test('N21 selected weekdays reach device and other days do not run',()=>{
  const f=fixture();schedule(f,1,[3]);f.step(60);assert.equal(f.device.s.active,null);
  assert.deepEqual(f.device.s.schedules[0].days,[3]);
  for(const days of [[7],[],[1,1]])assert.throws(()=>schedules([{schedule_id:'x',hour:7,minute:0,days,target_portion_g:20,enabled:true}],defaults));
});
test('N22 syncing and reboot preserve daily schedule execution key',()=>{
  const f=fixture();schedule(f);f.step(60);f.step(4);f.service.sync();f.boot();f.step(5);
  assert.equal(f.events().filter(e=>e.status==='SUCCESS').length,1);
  assert.equal(f.storage.all('device_schedule_runs').length,1);
});
test('N23 multiple overdue schedules create misses and no catch-up feeding',()=>{
  const f=fixture();f.service.setSchedules([8,12,18].map(h=>({schedule_id:`s${h}`,hour:h,minute:0,days:[1],target_portion_g:20,enabled:true})));
  f.device.tick();f.step(10*3600);assert.equal(f.device.s.active,null);
  assert.equal(f.events().filter(e=>e.status==='MISSED_SCHEDULE').length,2);
});
test('N24 repeat same ID returns old session, conflicting body is rejected',()=>{
  const f=fixture(),c=f.cmd();f.service.feed(c);f.service.feed(c);f.step(4);f.step(70);
  assert.equal(f.service.feed(c).status,'SUCCESS');assert.equal(f.backend.all('commands').length,1);
  assert.throws(()=>f.service.feed({...c,target_portion_g:40}),/COMMAND_ID_CONFLICT/);
});
test('N25 stale command is rejected at the device even when bypassing API',()=>{
  const f=fixture(),c=f.cmd();f.step(61);assert.equal(f.device.receive(c).status,'COMMAND_EXPIRED');assert.equal(f.device.s.active,null);
});
test('N26 duplicate events and late status cannot duplicate history or regress result',()=>{
  const f=fixture(),c=f.cmd();f.service.feed(c);f.step(4);const done=f.events().find(e=>e.status==='SUCCESS');
  const count=f.events().length;assert(f.service.event(done).duplicate);assert.equal(f.events().length,count);
  f.service.event({...done,event_id:'late-event',status:'DISPENSING',seq:done.seq+5});
  assert.equal(f.backend.get('commands',c.command_id).status,'SUCCESS');
});
test('N27 long feeding retains BUSY heartbeat and true disconnect becomes OFFLINE',()=>{
  const f=fixture();f.device.sensors.auto_feed=false;f.service.configure({feed_timeout_s:60});f.service.feed(f.cmd());
  f.step(25);assert.equal(f.service.state().connection,'BUSY');f.device.online=false;f.step(21);
  assert.equal(f.service.state().connection,'OFFLINE');
});
test('N28 strict validation rejects malformed values without changing stored config',()=>{
  const f=fixture();
  for(const v of [-1,0,NaN,'20',Infinity,501])assert.throws(()=>f.service.feed(f.cmd({target_portion_g:v})));
  assert.throws(()=>config({...defaults,food_stale_s:0}));
  assert.throws(()=>command(f.cmd({override:true}),defaults,f.now));
  assert.throws(()=>schedules([{schedule_id:'x',hour:25,minute:70,days:[1],target_portion_g:20,enabled:true}],defaults));
  assert.equal(f.device.s.active,null);
});
test('N26 event uniqueness survives closing and reopening SQLite database',()=>{
  const work=resolve(fileURLToPath(new URL('../../work/',import.meta.url)));mkdirSync(work,{recursive:true});
  const dir=mkdtempSync(join(work,'petfeeder-test-')),file=join(dir,'state.db');
  const e={event_id:'persisted-event',seq:1,status:'FOOD_LEFT',occurred_at:1800000000};
  let db=new Storage(file),s=new Service(db,{mode:'TEST',send(){}});s.event(e);db.close();
  db=new Storage(file);s=new Service(db,{mode:'TEST',send(){}});assert.equal(s.event(e).duplicate,true);db.close();
  assert(resolve(dir).startsWith(work+sep));rmSync(dir,{recursive:true,force:true});
});
test('measurement failure reports UNKNOWN and never becomes 0g food consumed',()=>{
  const f=fixture(),c=f.cmd();f.service.feed(c);f.step(4);f.device.sensors.weight_g=null;f.step(61);
  assert(f.events().some(e=>e.status==='UNKNOWN'));assert.equal(f.backend.get('commands',c.command_id).status,'SUCCESS');
});
test('config changed while BUSY is applied after completion through heartbeat version check',()=>{
  const f=fixture();f.service.feed(f.cmd());f.service.configure({food_stale_s:10});
  assert.notEqual(f.device.s.config.food_stale_s,10);f.step(4);
  assert.equal(f.device.s.config.food_stale_s,10);
  assert.equal(f.device.s.config_version,f.service.syncPayload().version);
});
test('daily UI summary counts all confirmed sessions even when history list is capped at 100',()=>{
  const f=fixture();for(let n=1;n<=105;n++)f.service.event({event_id:`daily-${n}`,command_id:`daily-cmd-${n}`,
    status:'SUCCESS',seq:n,occurred_at:f.now,actual_weight_g:1,target_portion_g:1});
  const state=f.service.state();assert.equal(state.commands.length,100);
  assert.equal(state.daily.actual_dispensed_g,105);assert.equal(state.daily.confirmed_sessions,105);
});
