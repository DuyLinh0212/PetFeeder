import test from 'node:test';
import assert from 'node:assert/strict';
import {Storage} from '../src/storage/database.mjs';
import {FeedingService} from '../src/services/feedingService.mjs';

function fixture(t){
  const store=new Storage(),sent=[];
  let now=1792500000,available=true;
  const service=new FeedingService(store,{mode:'TEST',send(kind,body){
    sent.push({kind,body});return available;
  }},()=>now);
  t.after(()=>store.close());
  return {service,sent,advance(seconds){now+=seconds;},setAvailable(value){available=value;},
    heartbeat(patch={}){service.heartbeat({occurred_at:now,busy:false,weight_g:0,
      boot_id:'current',config_version:service.syncPayload().version,...patch});}};
}

test('Repeated stale heartbeats and alternating boot IDs cannot flood sync',t=>{
  const f=fixture(t);
  f.heartbeat({occurred_at:1792499880,config_version:'old',boot_id:'old-simulator'});
  for(let n=0;n<14;n++){
    f.advance(1);
    f.heartbeat({occurred_at:1792499880,config_version:'old',boot_id:n%2?'old-simulator':'current'});
  }
  assert.equal(f.sent.length,1);
  f.advance(1);f.heartbeat({config_version:'old'});
  assert.equal(f.sent.length,2);
  assert.equal(f.sent[1].body.server_time,1792500015);
});

test('Matching live heartbeats stop resyncing after acknowledgement',t=>{
  const f=fixture(t);f.heartbeat();
  for(let n=0;n<20;n++){f.advance(5);f.heartbeat();}
  assert.equal(f.sent.length,1);
});

test('A newly detected clock error is corrected immediately, repeated drift is throttled',t=>{
  const f=fixture(t);f.heartbeat();
  f.advance(1);f.heartbeat({occurred_at:1792499990});
  assert.equal(f.sent.length,2);
  assert.equal(f.sent[1].body.version,f.sent[0].body.version);
  f.advance(5);f.heartbeat({occurred_at:1792499995});
  assert.equal(f.sent.length,2);
  f.advance(10);f.heartbeat({occurred_at:1792500005});
  assert.equal(f.sent.length,3);
});

test('Saving changed config bypasses heartbeat retry throttling',t=>{
  const f=fixture(t);f.heartbeat();
  const initialVersion=f.sent[0].body.version;
  f.service.configure({food_confirmed:true,food_label:'Hạt'});
  assert.equal(f.sent.length,2);
  assert.notEqual(f.sent[1].body.version,initialVersion);
  assert.equal(f.sent[1].body.config.food_label,'Hạt');
  f.advance(5);f.heartbeat({config_version:initialVersion});
  assert.equal(f.sent.length,3);
  f.advance(5);f.heartbeat({config_version:initialVersion});
  assert.equal(f.sent.length,3);
});

test('Pending config is retried immediately when dispensing finishes',t=>{
  const f=fixture(t);f.heartbeat({busy:true});
  const initialVersion=f.service.syncPayload().version;
  f.service.configure({food_stale_s:30});
  f.advance(1);f.heartbeat({busy:true,config_version:initialVersion});
  assert.equal(f.sent.length,3);
  f.advance(1);f.heartbeat({busy:false,config_version:initialVersion});
  assert.equal(f.sent.length,4);
  assert.equal(f.sent[3].body.config.food_stale_s,30);
});

test('Failed publish does not postpone the next sync attempt',t=>{
  const f=fixture(t);f.setAvailable(false);f.heartbeat({config_version:'old'});
  f.setAvailable(true);f.advance(1);f.heartbeat({config_version:'old'});
  assert.equal(f.sent.length,2);
});

test('A device returning after the offline timeout receives a fresh sync',t=>{
  const f=fixture(t);f.heartbeat();f.advance(21);f.heartbeat();
  assert.equal(f.sent.length,2);
});
