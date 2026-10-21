import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {createVisionRouter} from '../src/routes/vision.mjs';
async function setup(request){
 let evidence=null;const service={revokePet(){evidence=null;},observePet(boxes,{confirmed}){evidence={matched:confirmed&&boxes.length>0};return evidence;}};
 const app=express();app.use(createVisionRouter({request,service}));const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
 const base=`http://127.0.0.1:${server.address().port}`;
 const start=await(await fetch(base+'/start',{method:'POST'})).json();const session=start.data.session;
 return {base,session,get evidence(){return evidence;},send(){return fetch(base+'/detect',{method:'POST',headers:{'Content-Type':'application/octet-stream','X-Camera-Session':session},body:new Uint8Array([1,2,3])});},stop(){return fetch(base+'/stop',{method:'POST',headers:{'X-Camera-Session':session}});},close(){return new Promise(r=>server.close(r));}};
}
test('Only two fresh real-model frames authorize presence; stop revokes',async()=>{
 const f=await setup(async(url,options)=>{assert.equal(url,'http://127.0.0.1:8002/api/detect');assert.equal(options.body.get('file').size,3);return Response.json({success:true,detections:[{label:'cat',confidence:0.91}]});});
 try{assert.equal((await(await f.send()).json()).data.presence_verified,false);const result=(await(await f.send()).json()).data;
 assert.equal(result.presence_verified,true);assert.equal(result.identity_verified,false);assert.equal(result.detections[0].confidence,0.91);
 await f.stop();assert.equal(f.evidence,null);assert.equal((await f.send()).status,409);
 }finally{await f.close();}
});
test('Inference error revokes evidence instead of inventing a successful match',async()=>{
 const f=await setup(async()=>{throw Error('offline');});try{assert.equal((await f.send()).status,503);assert.equal(f.evidence,null);}finally{await f.close();}
});
test('In-flight result after stop cannot restore presence',async()=>{
 let release,entered;const processing=new Promise(r=>entered=r);const f=await setup(()=>new Promise(r=>{release=r;entered();}));
 try{const pending=f.send();await processing;await f.stop();release(Response.json({success:true,detections:[{label:'dog',confidence:0.95}]}));assert.equal((await pending).status,409);assert.equal(f.evidence,null);}finally{await f.close();}
});
