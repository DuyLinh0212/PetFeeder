import express from 'express';
import {randomUUID} from 'node:crypto';

export function createVisionRouter({url=process.env.YOLO_URL||'http://127.0.0.1:8002',request=fetch,service,clock=()=>Math.floor(Date.now()/1000)}={}) {
  const router=express.Router();let busy=false,session=null,streak=0,lastType=null,lastFrame=0;
  const revoke=()=>{streak=0;lastType=null;service?.revokePet();};
  router.post('/start',(req,res)=>{session=randomUUID();revoke();res.json({success:true,data:{session}});});
  router.post('/stop',(req,res)=>{
    if(req.get('X-Camera-Session')===session){session=null;revoke();}
    res.json({success:true,data:{stopped:true}});
  });
  router.post('/detect',express.raw({type:'application/octet-stream',limit:'2mb'}),async(req,res)=>{
    const owner=req.get('X-Camera-Session');
    if(!session||owner!==session)return res.status(409).json({success:false,message:'Phiên camera đã dừng. Mở camera lại.'});
    if(!Buffer.isBuffer(req.body)||!req.body.length)return res.status(400).json({success:false,message:'Thiếu ảnh camera.'});
    if(busy)return res.status(429).json({success:false,message:'YOLO đang xử lý khung hình trước.'});
    busy=true;const started=clock();
    try {
      const form=new FormData();form.append('file',new Blob([req.body]),'camera.jpg');form.append('confidence','0.5');
      const response=await request(`${url}/api/detect`,{method:'POST',body:form,signal:AbortSignal.timeout(8000)});
      if(!response.ok)throw new Error('YOLO_UNAVAILABLE');
      const result=await response.json();
      if(result.success!==true||!Array.isArray(result.detections))throw new Error('INVALID_YOLO_RESULT');
      if(session!==owner)return res.status(409).json({success:false,message:'Phiên camera đã dừng.'});
      const detections=result.detections.filter(b=>['cat','dog'].includes(b.label)&&Number.isFinite(b.confidence)&&b.confidence>=0.5&&b.confidence<=1);
      const best=[...detections].sort((a,b)=>b.confidence-a.confidence)[0];
      const fresh=clock()-started<3;
      if(best&&fresh){streak=lastType===best.label&&started-lastFrame<3?streak+1:1;lastType=best.label;lastFrame=started;}
      else {streak=0;lastType=null;}
      const evidence=service?.observePet(fresh?detections:[],{issuedAt:started,confirmed:streak>=2});
      res.json({success:true,data:{...result,detections:fresh?detections:[],source:'YOLO11N',identity_verified:false,
        presence_verified:evidence?.matched===true,consecutive_frames:streak,fresh}});
    } catch(error) {
      if(session===owner)revoke();
      res.status(503).json({success:false,message:'Chưa nhận được kết quả YOLO. Kiểm tra server camera cổng 8002.'});
    } finally {busy=false;}
  });
  return router;
}
