import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:net';
import {once} from 'node:events';
import {mkdtempSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {Aedes} from 'aedes';
import mqtt from 'mqtt';
import {createIntegration} from '../src/long/integration.mjs';

const waitFor=async fn=>{for(let n=0;n<150;n++){if(fn())return;await new Promise(r=>setTimeout(r,20));}throw new Error('MQTT condition timed out');};
test('Main MQTT prefix: command reaches device, ack follows durable dedup, restart rejects retained events',async()=>{
  const broker=await Aedes.createBroker();
  const tcp=createServer(broker.handle);tcp.listen(0,'127.0.0.1');await once(tcp,'listening');
  const url=`mqtt://127.0.0.1:${tcp.address().port}`,prefix='test/petfeeder/main';
  const dataDir=mkdtempSync(join(tmpdir(),'petfeeder-main-mqtt-'));
  const device=mqtt.connect(url,{reconnectPeriod:0});await once(device,'connect');
  let integration;const received=[],acks=[];
  device.on('message',(topic,body)=>{
    if(topic===`${prefix}/command`)received.push(JSON.parse(body));
    if(topic===`${prefix}/ack`)acks.push(JSON.parse(body));
  });
  await new Promise((resolve,reject)=>device.subscribe([`${prefix}/command`,`${prefix}/sync`,`${prefix}/ack`],{qos:1},e=>e?reject(e):resolve()));
  const publish=(topic,body,retain=false)=>new Promise((resolve,reject)=>device.publish(`${prefix}/${topic}`,JSON.stringify(body),{qos:1,retain},e=>e?reject(e):resolve()));
  try{
    integration=createIntegration({dataDir,brokerUrl:url,prefix});
    integration.service.configure({food_confirmed:true,food_label:'Main owner confirmation'});
    await waitFor(()=>integration.connected());
    const now=Math.floor(Date.now()/1000);
    await publish('telemetry',{occurred_at:now,busy:false,weight_g:0,device_id:'petfeeder_01',sensor_mode:'HX711_MANUAL'});
    await waitFor(()=>integration.service.state().connection==='ONLINE');
    const c={command_id:'mqtt-main-1',source:'APP',target_portion_g:20,override:false,created_at:now,expires_at:now+60};
    integration.service.feed(c);await waitFor(()=>received.length===1);
    assert.deepEqual(received[0],c);
    const e={event_id:'main-event-1',command_id:c.command_id,status:'SUCCESS',seq:1,occurred_at:now,actual_weight_g:20,target_portion_g:20,source:'APP'};
    for(let n=0;n<3;n++)await publish('events',e);
    await waitFor(()=>acks.length===3);
    assert.equal(integration.db.all('events').length,1);
    assert.equal(integration.service.state().daily.actual_dispensed_g,20);
    await publish('events',{...e,event_id:'late-progress',status:'DISPENSING',seq:99,actual_weight_g:0});
    await waitFor(()=>acks.length===4);
    assert.equal(integration.db.get('commands',c.command_id).status,'SUCCESS');
    integration.close();integration=null;
    await new Promise(r=>setTimeout(r,100));
    await publish('events',{...e,event_id:'retained-replay',command_id:'retained-session'},true);
    integration=createIntegration({dataDir,brokerUrl:url,prefix});
    await waitFor(()=>integration.connected());
    await new Promise(r=>setTimeout(r,100));
    assert.equal(integration.db.get('events','retained-replay'),null);
    await publish('events',e);await waitFor(()=>acks.length===5);
    assert.equal(integration.db.all('commands').length,1);
    assert.equal(integration.service.state().daily.actual_dispensed_g,20);
  }finally{
    integration?.close();await new Promise(r=>device.end(true,r));
    await new Promise(r=>broker.close(r));await new Promise(r=>tcp.close(r));
    rmSync(dataDir,{recursive:true,force:true});
  }
});
