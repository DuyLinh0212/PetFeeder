import test from 'node:test';
import assert from 'node:assert/strict';
import {Storage} from '../src/storage/database.mjs';
import {FeedingService} from '../src/services/feedingService.mjs';
import {DeviceSimulator} from './helpers/deviceSimulator.mjs';

async function fixture(t){
  let now=Date.parse('2026-10-19T00:00:00Z')/1000,device,next=0;
  const backend=new Storage(),deviceStore=new Storage();let pending=Promise.resolve();
  const service=new FeedingService(backend,{mode:'TEST',send(kind,payload){
    if(!device?.online)return false;
    if(kind==='sync')device.sync(payload);
    else if(kind==='command')device.receive(payload);
    return true;
  }},()=>now);
  const queue=work=>{pending=pending.then(work);return pending;};
  const flushEvents=()=>pending;
  const boot=async()=>{
    device=new DeviceSimulator(deviceStore,event=>queue(()=>service.event(event)),heartbeat=>queue(()=>service.heartbeat(heartbeat)),()=>now);
    await service.sync();device.heartbeat();await flushEvents();
  };
  await boot();
  t.after(()=>{backend.close();deviceStore.close();});
  return {backend,deviceStore,service,boot,get device(){return device;},
    command(source='APP',portion=20){return {command_id:`active-${++next}`,source,target_portion_g:portion,created_at:now,expires_at:now+60};},
    async step(seconds){now+=seconds;device.tick();await flushEvents();},flushEvents};
}

test('C03 duplicate IDs and simultaneous sources cannot start a second session',async t=>{
  const f=await fixture(t),first=f.command();await f.service.feed(first);await f.flushEvents();
  const activeId=f.device.s.active.command_id;
  await f.service.feed(first);
  assert.equal(f.device.s.active.command_id,activeId);
  assert.equal((await f.service.feed(f.command('BUTTON'))).error_code,'BUSY');
  assert.equal((await f.service.feed(f.command('SCHEDULE'))).error_code,'BUSY');
  assert.equal(f.deviceStore.all('device_totals')[0].feeds,1);
});

test('N01 portion is additional to bowl weight and cannot exceed bowl capacity',async t=>{
  const fits=await fixture(t);fits.device.sensors.weight_g=130;fits.device.heartbeat();await fits.flushEvents();
  const accepted=await fits.service.feed(fits.command());await fits.flushEvents();
  assert.equal(accepted.command_id,fits.device.s.active.command_id);
  assert.equal(fits.device.s.active.target_portion_g,20);
  assert.equal((await fits.service.state()).commands.find(row=>row.command_id===accepted.command_id).status,'DISPENSING');

  const overflow=await fixture(t);overflow.device.sensors.weight_g=140;overflow.device.heartbeat();await overflow.flushEvents();
  assert.equal((await overflow.service.feed(overflow.command())).error_code,'BOWL_FULL');
  assert.equal(overflow.device.s.active,null);
});

test('N02 daily feed count survives reboot and resets on the next day',async t=>{
  const f=await fixture(t);await f.service.configure({max_daily_feeds:2});
  for(let n=0;n<2;n++){await f.service.feed(f.command());await f.flushEvents();await f.step(4);await f.step(181);}
  await f.boot();
  assert.equal((await f.service.feed(f.command())).error_code,'DAILY_FEED_LIMIT');
  await f.step(86400);
  const nextDay=await f.service.feed(f.command());await f.flushEvents();
  assert.equal(f.device.s.active.command_id,nextDay.command_id);
  assert.equal((await f.service.state()).commands.find(row=>row.command_id===nextDay.command_id).status,'DISPENSING');
});

test('N07/N09 scale interference or negative HX711 bowl-removal proxy stops without a measured result',async t=>{
  const f=await fixture(t),first=f.command();f.device.sensors.weight_g=30;f.device.heartbeat();await f.flushEvents();
  await f.service.feed(first);f.device.sensors.weight_g=25;await f.step(1);
  assert.equal(f.backend.get('commands',first.command_id).status,'INTERRUPTED');
  assert.equal(f.backend.get('commands',first.command_id).actual_weight_g,null);

  f.device.reconcile();await f.step(181);
  const second=f.command();await f.service.feed(second);f.device.sensors.weight_g=-12;await f.step(1);
  assert.equal(f.backend.get('commands',second.command_id).error_code,'BOWL_MISSING');
  assert.equal(f.backend.get('commands',second.command_id).actual_weight_g,null);
});

test('N19 offline schedule executes once and queued events replay after reconnect',async t=>{
  const f=await fixture(t);
  await f.service.setSchedules([{schedule_id:'breakfast',hour:7,minute:1,days:[1],target_portion_g:20,enabled:true}]);
  f.device.tick();f.device.online=false;await f.step(60);await f.step(4);
  assert(f.device.s.queue.length>0);
  f.device.online=true;f.device.flush();f.device.tick();await f.flushEvents();
  assert.equal(f.backend.all('events').filter(event=>event.status==='SUCCESS').length,1);
  assert.equal(f.backend.all('events').filter(event=>event.status==='MISSED_SCHEDULE').length,0);
});
