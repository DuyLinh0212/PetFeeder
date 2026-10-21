import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,mkdirSync,rmSync,writeFileSync} from 'node:fs';
import {resolve,join,sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {once} from 'node:events';
test('HTTP server end-to-end: serve UI, validate, dispense, retry, reboot, history',async()=>{
  const work=resolve(fileURLToPath(new URL('../../work/',import.meta.url)));mkdirSync(work,{recursive:true});
  const dir=mkdtempSync(join(work,'http-test-'));
  const app=join(dir,'app');mkdirSync(app);
  writeFileSync(join(app,'index.html'),'<!doctype html><title>PetFeeder</title><script src="flutter_bootstrap.js"></script>');
  writeFileSync(join(app,'flutter_bootstrap.js'),'// Flutter build fixture for static serving test\n'.repeat(4));
  const child=spawn(process.execPath,[fileURLToPath(new URL('../src/server.js',import.meta.url)),'--demo'],
    {env:{...process.env,PORT:'0',DATA_DIR:dir,APP_DIR:app},stdio:['ignore','pipe','pipe'],windowsHide:true});
  let stdout='',stderr='';child.stdout.on('data',b=>stdout+=b);child.stderr.on('data',b=>stderr+=b);
  try{
    for(let n=0;n<100&&!stdout.includes('http://');n++)await new Promise(r=>setTimeout(r,30));
    const url=stdout.match(/http:\/\/127\.0\.0\.1:\d+/)?.[0];assert(url,stderr||stdout);
    async function request(path,body){const r=await fetch(url+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});return {status:r.status,body:await r.json()};}
    assert((await(await fetch(url)).text()).includes('PetFeeder'));
    const debug=await fetch(url+'/debug');assert.equal(debug.status,200);assert((await debug.text()).includes('Thiết bị giả lập'));
    const bootstrap=await fetch(url+'/flutter_bootstrap.js');assert.equal(bootstrap.status,200);assert((await bootstrap.text()).length>100);
    assert.equal((await request('/api/state')).body.mode,'DEMO');
    assert.equal((await request('/api/config',{food_confirmed:true,food_label:'HTTP test'})).status,200);
    const id=(await request('/api/id')).body;
    const cmd={command_id:id.command_id,created_at:id.now,expires_at:id.now+id.ttl_s,source:'APP',target_portion_g:20,override:false};
    assert.equal((await request('/api/feeding',cmd)).body.status,'DISPENSING');
    await request('/api/demo',{advance_s:5});
    const retried=(await request('/api/feeding',cmd)).body;assert.equal(retried.status,'SUCCESS');assert.equal(retried.actual_weight_g,20);
    const hist=(await request('/api/history')).body;assert.equal(hist.commands.length,1);assert.equal(hist.events.filter(e=>e.status==='SUCCESS').length,1);
    const invalid=await request('/api/feeding',{...cmd,command_id:'bad-input',target_portion_g:'20'});assert.equal(invalid.status,400);
    await request('/api/demo',{restart:true});
    assert.equal((await request('/api/feeding',cmd)).body.status,'SUCCESS');
    assert.equal((await request('/api/history')).body.commands.length,1);
    const state=(await request('/api/state')).body;assert.equal(state.device.weight_g,20);
  }finally{
    const exit=once(child,'exit');child.kill('SIGTERM');await exit;
    const checked=resolve(dir);assert(checked.startsWith(work+sep));rmSync(checked,{recursive:true,force:true});
  }
});
