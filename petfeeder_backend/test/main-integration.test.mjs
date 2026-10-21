import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {mkdtempSync,rmSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {once} from 'node:events';
import {createIntegration} from '../src/long/integration.mjs';

test('Main Flutter REST contract uses durable IDs, validates schedules and retains dedup after hiding history',async()=>{
  const dir=mkdtempSync(join(tmpdir(),'petfeeder-main-'));
  const sent=[];let now=1792500000;
  const integration=createIntegration({dataDir:dir,clock:()=>now,transport:{mode:'TEST',send(k,p){sent.push([k,p]);return true;}}});
  const app=express();app.use(express.json());app.use('/api',integration.router);
  const server=app.listen(0,'127.0.0.1');await once(server,'listening');
  const base=`http://127.0.0.1:${server.address().port}/api`;
  async function request(path,body,method=body===undefined?'GET':'POST'){
    const response=await fetch(base+path,{method,headers:{'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});
    return {status:response.status,body:await response.json()};
  }
  try{
    assert.equal((await request('/device/status')).body.data.online,false);
    assert.equal((await request('/device/status')).body.data.bowl_weight_g,null);
    await request('/device/config',{food_confirmed:true,food_label:'Hạt chủ đã kiểm tra'},'PUT');
    integration.service.heartbeat({occurred_at:now,busy:false,weight_g:0,boot_id:'test',config_version:integration.service.syncPayload().version});
    const id=(await request('/id')).body;
    const cmd={command_id:id.command_id,portion:20,override:false,created_at:id.now,expires_at:id.now+id.ttl_s};
    assert.equal((await request('/feeding/feed',{portion:20,override:false})).body.code,'COMMAND_ID_REQUIRED');
    assert.equal((await request('/feeding/feed',cmd)).body.data.status,'QUEUED');
    assert.equal(sent.filter(([k])=>k==='command').length,1);
    assert.equal((await request('/feeding/feed',cmd)).body.data.status,'QUEUED');
    assert.equal(sent.filter(([k])=>k==='command').length,1);
    assert.equal((await request('/feeding/feed',{...cmd,portion:40})).body.code,'COMMAND_ID_CONFLICT');
    integration.onMessage('duylinh0212/petfeeder/v1/events',Buffer.from(JSON.stringify({event_id:'done',command_id:cmd.command_id,seq:1,occurred_at:now,status:'SUCCESS',actual_weight_g:20,target_portion_g:20,source:'APP'})));
    const history=(await request('/feeding/history')).body.data;
    assert.equal(history.length,1);assert.equal(history[0].actual_weight_g,20);
    await request('/feeding/history',undefined,'DELETE');
    assert.equal((await request('/feeding/history')).body.data.length,0);
    assert.equal((await request('/feeding/feed',cmd)).body.data.status,'SUCCESS');
    assert.equal(integration.service.state().daily.actual_dispensed_g,20);
    const valid={name:'Bữa thứ hai',time:'07:30',portion_g:20,days:['T2'],enabled:true};
    const sch=await request('/schedules',valid);assert.equal(sch.status,201);
    assert.deepEqual(integration.service.state().schedules[0].days,[1]);
    assert.equal((await request('/schedules',{...valid,time:'25:70'})).status,400);
    assert.equal((await request('/schedules',{...valid,days:[]})).status,400);
    assert.equal((await request('/schedules',{...valid,portion_g:'20'})).status,400);
    assert.equal((await request('/device/config',{safe_interval_sec:-1},'PUT')).status,400);
    assert.equal(integration.service.state().schedules.length,1);
    integration.onMessage('duylinh0212/petfeeder/v1/events',Buffer.from(JSON.stringify({event_id:'interrupted',command_id:'offline-session',seq:2,occurred_at:now,status:'INTERRUPTED',actual_weight_g:null})),{retain:false});
    assert.equal((await request('/feeding/history')).body.data[0].actual_weight_g,null);
    now+=21;assert.equal((await request('/device/status')).body.data.online,false);
    integration.service.event({event_id:'jammed-session',command_id:'jammed-command',seq:1,occurred_at:now,status:'JAM_ERROR',actual_weight_g:8,target_portion_g:20,source:'APP'});
    now+=181;
    integration.service.heartbeat({occurred_at:now,busy:false,weight_g:8,boot_id:'test',config_version:integration.service.syncPayload().version});
    const recoveryId=(await request('/id')).body;
    const recovery={command_id:recoveryId.command_id,portion:12,override:false,created_at:recoveryId.now,expires_at:recoveryId.now+recoveryId.ttl_s,retry_of:'jammed-command'};
    assert.equal((await request('/feeding/feed',recovery)).body.data.status,'QUEUED');
    assert.deepEqual(sent.find(([kind,body])=>kind==='command'&&body.command_id===recovery.command_id)[1],{
      command_id:recovery.command_id,source:'APP',target_portion_g:12,override:false,created_at:recovery.created_at,expires_at:recovery.expires_at,retry_of:'jammed-command'});
    assert.equal((await request('/feeding/feed',recovery)).body.data.command_id,recovery.command_id);
    assert.equal(sent.filter(([kind,body])=>kind==='command'&&body.command_id===recovery.command_id).length,1);
  }finally{await new Promise(r=>server.close(r));integration.close();rmSync(dir,{recursive:true,force:true});}
});

test('The integrated circuit preserves every main component and every original wire',()=>{
  const current=JSON.parse(readFileSync(new URL('../../PetFeeder/diagram.json',import.meta.url),'utf8'));
  const original=JSON.parse(readFileSync(new URL('./fixtures/main-circuit-baseline.json',import.meta.url),'utf8'));
  assert.deepEqual(current.connections,original.connections);
  assert.deepEqual(current.parts.map(p=>[p.id,p.type,p.top,p.left]),original.parts);
  assert.equal(current.parts.filter(p=>p.type==='board-esp32-devkit-c-v4').length,1);
  assert.equal(current.parts.filter(p=>p.type==='wokwi-servo').length,2);
});
