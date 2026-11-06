import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:net';
import {once} from 'node:events';
import {mkdtempSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {Aedes} from 'aedes';
import mqtt from 'mqtt';
import {createBackend} from '../src/app.mjs';

const waitFor=async fn=>{
  for(let n=0;n<150;n++){if(await fn())return;await new Promise(resolve=>setTimeout(resolve,20));}
  throw new Error('MQTT condition timed out');
};

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
  await new Promise((resolve,reject)=>device.subscribe([`${prefix}/command`,`${prefix}/sync`,`${prefix}/ack`],{qos:1},error=>error?reject(error):resolve()));
  const publish=(topic,body,retain=false)=>new Promise((resolve,reject)=>device.publish(`${prefix}/${topic}`,JSON.stringify(body),{qos:1,retain},error=>error?reject(error):resolve()));
  try{
    integration=await createBackend({dataDir,brokerUrl:url,prefix});
    await waitFor(()=>integration.connected());
    const now=Math.floor(Date.now()/1000);
    await publish('telemetry',{occurred_at:now,busy:false,weight_g:0,device_id:'petfeeder_01',sensor_mode:'HX711_MANUAL'});
    await waitFor(async()=> (await integration.service.state()).connection==='ONLINE');
    const c={command_id:'mqtt-main-1',source:'APP',target_portion_g:20,created_at:now,expires_at:now+60};
    await integration.service.feed(c);await waitFor(()=>received.length>=1);
    assert.deepEqual(received[0],c);
    const e={event_id:'main-event-1',command_id:c.command_id,status:'SUCCESS',seq:1,occurred_at:now,actual_weight_g:20,target_portion_g:20,source:'APP'};
    for(let n=0;n<3;n++)await publish('events',e);
    await waitFor(()=>acks.filter(a=>a.event_id===e.event_id).length>=3);
    assert.equal(integration.db.all('events').length,1);
    assert.equal((await integration.service.state()).daily.actual_dispensed_g,20);
    await publish('events',{...e,event_id:'late-progress',status:'DISPENSING',seq:99,actual_weight_g:0});
    await waitFor(()=>acks.some(a=>a.event_id==='late-progress'));
    assert.equal(integration.db.get('commands',c.command_id).status,'SUCCESS');
    await integration.close();integration=null;
    await new Promise(resolve=>setTimeout(resolve,100));
    await publish('events',{...e,event_id:'retained-replay',command_id:'retained-session'},true);
    integration=await createBackend({dataDir,brokerUrl:url,prefix});
    await waitFor(()=>integration.connected());
    await new Promise(resolve=>setTimeout(resolve,100));
    assert.equal(integration.db.get('events','retained-replay'),null);
    await publish('events',e);await waitFor(()=>acks.filter(a=>a.event_id===e.event_id).length>=4);
    assert.equal(integration.db.all('commands').length,1);
    assert.equal((await integration.service.state()).daily.actual_dispensed_g,20);
  }finally{
    if(integration)await integration.close();
    await new Promise(resolve=>device.end(true,resolve));
    await new Promise(resolve=>broker.close(resolve));await new Promise(resolve=>tcp.close(resolve));
    rmSync(dataDir,{recursive:true,force:true});
  }
});

test('Backends in separate namespaces on one broker keep independent MQTT connections',async()=>{
  const broker=await Aedes.createBroker(),tcp=createServer(broker.handle);
  tcp.listen(0,'127.0.0.1');await once(tcp,'listening');
  const url=`mqtt://127.0.0.1:${tcp.address().port}`;
  const dirs=[mkdtempSync(join(tmpdir(),'petfeeder-sync-a-')),mkdtempSync(join(tmpdir(),'petfeeder-sync-b-'))];
  const observer=mqtt.connect(url,{reconnectPeriod:0});await once(observer,'connect');
  const backends=[];
  try{
    backends.push(await createBackend({dataDir:dirs[0],brokerUrl:url,prefix:'test/sync/a'}));
    await waitFor(()=>backends[0].connected());
    backends.push(await createBackend({dataDir:dirs[1],brokerUrl:url,prefix:'test/sync/b'}));
    await waitFor(()=>backends[1].connected());
    const version=(await backends[0].service.syncPayload()).version;
    await new Promise((resolve,reject)=>observer.publish('test/sync/a/telemetry',JSON.stringify({
      occurred_at:Math.floor(Date.now()/1000),busy:false,weight_g:12,boot_id:'simulator-a',config_version:version,
    }),{qos:1},error=>error?reject(error):resolve()));
    await waitFor(async()=> (await backends[0].service.state()).connection==='ONLINE');
    assert(backends.every(backend=>backend.connected()));
    assert.equal((await backends[0].service.state()).device.weight_g,12);
    assert.equal((await backends[1].service.state()).connection,'OFFLINE');
  }finally{
    await Promise.all(backends.map(backend=>backend.close()));
    await new Promise(resolve=>observer.end(true,resolve));
    await new Promise(resolve=>broker.close(resolve));await new Promise(resolve=>tcp.close(resolve));
    dirs.forEach(dir=>rmSync(dir,{recursive:true,force:true}));
  }
});
