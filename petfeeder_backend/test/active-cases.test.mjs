import test from 'node:test';
import assert from 'node:assert/strict';
import {Storage} from '../src/storage/database.mjs';
import {FeedingService} from '../src/services/feedingService.mjs';
import {DeviceSimulator} from './helpers/deviceSimulator.mjs';

function fixture(t){
  let now=Date.parse('2026-10-19T00:00:00Z')/1000,device,next=0;
  const backend=new Storage(),deviceStore=new Storage();
  const service=new FeedingService(backend,{mode:'TEST',send(kind,payload){
    if(!device?.online)return false;
    if(kind==='sync')device.sync(payload);
    else if(kind==='identity')device.setIdentity(payload);
    else if(kind==='command')device.receive(payload);
    return true;
  }},()=>now);
  const boot=()=>{
    device=new DeviceSimulator(deviceStore,event=>service.event(event),heartbeat=>service.heartbeat(heartbeat),()=>now);
    service.sync();device.heartbeat();
  };
  boot();
  t.after(()=>{backend.close();deviceStore.close();});
  return {backend,deviceStore,service,boot,get device(){return device;},
    command(source='APP',portion=20){return {command_id:`active-${++next}`,source,target_portion_g:portion,created_at:now,expires_at:now+60};},
    step(seconds){now+=seconds;device.tick();}};
}

test('C01 unknown pet is rejected when identity verification is enabled',t=>{
  const f=fixture(t);f.service.configure({require_pet:true});
  assert.equal(f.service.feed(f.command()).error_code,'UNKNOWN_PET');
  assert.equal(f.device.s.active,null);
});

test('C03 duplicate IDs and simultaneous sources cannot start a second session',t=>{
  const f=fixture(t),first=f.command();f.service.feed(first);
  const activeId=f.device.s.active.command_id;
  f.service.feed(first);
  assert.equal(f.device.s.active.command_id,activeId);
  assert.equal(f.service.feed(f.command('BUTTON')).error_code,'BUSY');
  assert.equal(f.service.feed(f.command('SCHEDULE')).error_code,'BUSY');
  assert.equal(f.deviceStore.all('device_totals')[0].feeds,1);
});

test('N01 a new portion is blocked when it would exceed bowl capacity',t=>{
  const f=fixture(t);f.device.sensors.weight_g=140;f.device.heartbeat();
  assert.equal(f.service.feed(f.command()).error_code,'BOWL_FULL');
  assert.equal(f.device.s.active,null);
});

test('N02 daily feed count survives reboot and resets on the next day',t=>{
  const f=fixture(t);f.service.configure({max_daily_feeds:2});
  for(let n=0;n<2;n++){f.service.feed(f.command());f.step(4);f.step(181);}
  f.boot();
  assert.equal(f.service.feed(f.command()).error_code,'DAILY_FEED_LIMIT');
  f.step(86400);
  assert.equal(f.service.feed(f.command()).status,'DISPENSING');
});

test('N07/N09 scale interference or negative HX711 bowl-removal proxy stops without a measured result',t=>{
  const f=fixture(t),first=f.command();f.device.sensors.weight_g=30;f.device.heartbeat();
  f.service.feed(first);f.device.sensors.weight_g=25;f.step(1);
  assert.equal(f.backend.get('commands',first.command_id).status,'INTERRUPTED');
  assert.equal(f.backend.get('commands',first.command_id).actual_weight_g,null);

  f.device.reconcile();f.step(181);
  const second=f.command();f.service.feed(second);f.device.sensors.weight_g=-12;f.step(1);
  assert.equal(f.backend.get('commands',second.command_id).error_code,'BOWL_MISSING');
  assert.equal(f.backend.get('commands',second.command_id).actual_weight_g,null);
});

test('N19 offline schedule executes once and queued events replay after reconnect',t=>{
  const f=fixture(t);
  f.service.setSchedules([{schedule_id:'breakfast',hour:7,minute:1,days:[1],target_portion_g:20,enabled:true}]);
  f.device.tick();f.device.online=false;f.step(60);f.step(4);
  assert(f.device.s.queue.length>0);
  f.device.online=true;f.device.flush();f.device.tick();
  assert.equal(f.backend.all('events').filter(event=>event.status==='SUCCESS').length,1);
  assert.equal(f.backend.all('events').filter(event=>event.status==='MISSED_SCHEDULE').length,0);
});
