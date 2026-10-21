import test from 'node:test';
import assert from 'node:assert/strict';
import {Storage} from '../src/storage/database.mjs';
import {FeedingService as Service} from '../src/services/feedingService.mjs';
import {DeviceSimulator} from './helpers/deviceSimulator.mjs';

function fixture(){
  let now=1792500000,device,service,next=0;
  const backend=new Storage(),deviceStore=new Storage();
  const transport={mode:'TEST',send(kind,p){
    if(!device)return false;
    if(kind==='sync')device.sync(p);
    else if(kind==='identity')device.setIdentity(p);
    else if(kind==='command')device.receive(p);
    return true;
  }};
  service=new Service(backend,transport,()=>now);
  const boot=()=>{device=new DeviceSimulator(deviceStore,e=>service.event(e),h=>service.heartbeat(h),()=>now);service.sync();device.heartbeat();};
  boot();service.configure({require_pet:true});
  return {service,backend,deviceStore,boot,get device(){return device;},get now(){return now;},
    command(){return {command_id:`camera-cmd-${++next}`,source:'APP',target_portion_g:20,created_at:now,expires_at:now+60};},
    verify(){return service.observePet([{label:'cat',confidence:0.91}]);},
    step(seconds){now+=seconds;device.tick();},close(){backend.close();deviceStore.close();}};
}

test('Real YOLO proof reaches ESP32 and retries cannot dispense twice',()=>{
 const f=fixture();try{
 const p=f.verify();assert.equal(p.source,'YOLO_PET_PRESENCE');assert.equal(p.confidence,0.91);
 const c=f.command();assert.equal(f.service.feed(c).status,'DISPENSING');
 for(let i=0;i<10;i++)f.step(1);
 const result=f.service.feed(c);assert.equal(result.status,'SUCCESS');assert.equal(result.actual_weight_g,20);
 assert.equal(result.identity_context.confidence_kind,'MODEL');
 }finally{f.close();}
});
for(const [label,boxes] of [['none',[]],['low score',[{label:'cat',confidence:0.49}]],['person',[{label:'person',confidence:0.99}]],['invalid',[{label:'dog',confidence:NaN}]]])test('Blocks '+label,()=>{
 const f=fixture();try{f.service.observePet(boxes);assert.equal(f.service.feed(f.command()).error_code,'UNKNOWN_PET');}finally{f.close();}
});
test('Revocation and expiry block new feeds, posted confidence cannot bypass YOLO',()=>{
 const f=fixture();try{f.verify();f.service.revokePet();assert.equal(f.service.feed({...f.command(),confidence:1,pet_id:'species-cat',
 recognition_id:'client-asserted',recognition_expires_at:f.now+5,recognition_source:'YOLO_PET_PRESENCE'}).error_code,'UNKNOWN_PET');
 f.verify();f.step(6);assert.equal(f.service.feed(f.command()).error_code,'UNKNOWN_PET');
 }finally{f.close();}
});
