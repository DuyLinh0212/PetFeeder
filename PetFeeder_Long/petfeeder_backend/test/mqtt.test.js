import test from 'node:test';
import assert from 'node:assert/strict';
import aedes from 'aedes';
import {createServer} from 'node:net';
import mqtt from 'mqtt';
import {once} from 'node:events';
import {Storage} from '../src/storage.js';
import {Service} from '../src/service.js';
import {mqttTransport} from '../src/mqttClient.js';
const delay=ms=>new Promise(r=>setTimeout(r,ms));
async function until(predicate){for(let i=0;i<100;i++){if(predicate())return;await delay(20);}throw Error('MQTT integration timed out');}
test('actual local MQTT: command delivery, persistent event de-duplication, ack and retained rejection',async()=>{
  const broker=aedes(),net=createServer(broker.handle);net.listen(0,'127.0.0.1');await once(net,'listening');
  const url=`mqtt://127.0.0.1:${net.address().port}`;process.env.MQTT_URL=url;process.env.DEVICE_ID='integration-device';
  const db=new Storage();let service;
  let transport=mqttTransport(()=>service);service=new Service(db,transport);
  const esp=mqtt.connect(url,{clientId:'fake-esp'});await once(esp,'connect');
  const received=[],acks=[];
  esp.on('message',(topic,p)=>{const b=JSON.parse(p.toString());if(topic.endsWith('/command'))received.push(b);if(topic.endsWith('/ack'))acks.push(b);});
  await new Promise((r,j)=>esp.subscribe(['petfeeder/integration-device/command','petfeeder/integration-device/ack'],{qos:1},e=>e?j(e):r()));
  try{
    const now=Math.floor(Date.now()/1000);service.configure({food_confirmed:true,food_label:'test'});
    service.heartbeat({occurred_at:now,busy:false,weight_g:0});
    const c={command_id:'mqtt-case-1',source:'APP',target_portion_g:20,created_at:now,expires_at:now+60,override:false};
    service.feed(c);await until(()=>received.length===1);assert.equal(received[0].command_id,c.command_id);
    const e={event_id:'mqtt-event-1',seq:1,command_id:c.command_id,status:'SUCCESS',target_portion_g:20,actual_weight_g:19.5,occurred_at:now};
    for(let n=0;n<3;n++)esp.publish('petfeeder/integration-device/event',JSON.stringify(e),{qos:1,retain:false});
    await until(()=>acks.length===3);assert.equal(db.all('events').length,1);assert.equal(db.get('commands',c.command_id).status,'SUCCESS');
    // Retained publish made while backend is disconnected must be ignored on its new subscription.
    transport.close();await delay(100);
    await new Promise((r,j)=>esp.publish('petfeeder/integration-device/event',JSON.stringify({...e,event_id:'retained-old'}),{qos:1,retain:true},error=>error?j(error):r()));
    const count=db.all('events').length;
    transport=mqttTransport(()=>service);service.transport=transport;await delay(250);
    assert.equal(db.all('events').length,count);assert.equal(acks.length,3);
    const reader=mqtt.connect(url,{clientId:'retained-reader'});await once(reader,'connect');
    let packet;
    reader.on('message',(_t,_p,p)=>{packet=p;});reader.subscribe('petfeeder/integration-device/event');
    await until(()=>packet);assert.equal(packet.retain,true);assert.equal(db.all('events').length,count);
    await new Promise(r=>reader.end(false,r));
  }finally{
    await new Promise(r=>esp.end(false,r));transport.close();await delay(50);
    await new Promise(r=>broker.close(r));await new Promise(r=>net.close(r));db.close();
  }
});
