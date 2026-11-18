const express = require('express');
const cors = require('cors');
const http = require('node:http');
const path = require('node:path');
const {performance} = require('node:perf_hooks');
const {createHash,timingSafeEqual} = require('node:crypto');
const {WebSocketServer,WebSocket} = require('ws');
const config = require('./config');

async function startServer(backendOptions = {}) {
  const token=process.env.PETFEEDER_API_TOKEN;
  if(process.env.RENDER==='true'&&!token)throw new Error('PETFEEDER_API_TOKEN is required on Render');
  const digest=value=>createHash('sha256').update(value).digest();
  const authorization=token?digest(`Bearer ${token}`):null;
  const websocketToken=token?digest(`petfeeder.token.${Buffer.from(token).toString('base64url')}`):null;
  const {createBackend} = await import('./app.mjs');
  const integration=await createBackend({brokerUrl:config.mqtt.brokerUrl,databaseUrl:process.env.DATABASE_URL,
    prefix:process.env.MQTT_TOPIC_PREFIX||'duylinh0212/petfeeder/v1', ...backendOptions});
  const app=express();
  app.use((req,res,next)=>{
    if(req.path!=='/api'&&!req.path.startsWith('/api/'))return next();
    const startedAt=performance.now();
    res.once('finish',()=>console.log(`[API] ${req.method} ${req.path} ${res.statusCode} ${Math.round(performance.now()-startedAt)}ms`));
    next();
  });
  app.use(cors());app.use(express.json({limit:'32kb'}));
  app.use('/api',(req,res,next)=>{
    if(!authorization||timingSafeEqual(authorization,digest(req.get('authorization')||'')))return next();
    res.set('WWW-Authenticate','Bearer');
    res.status(401).json({success:false,code:'UNAUTHORIZED',message:'Khóa truy cập máy chủ chưa đúng.'});
  });
  app.use('/api',integration.router);
  app.get('/health',async(req,res)=>{
    try {
      await integration.db.health?.();
      res.json({status:'OK',database_connected:true,mqtt_connected:integration.connected()});
    } catch {
      res.status(503).json({status:'DEGRADED',database_connected:false,mqtt_connected:integration.connected()});
    }
  });
  app.get('/api',(req,res)=>res.json({name:'PetFeeder Backend',device:'/api/device/status',schedules:'/api/schedules',
    feeding:'/api/feeding/feed',history:'/api/feeding/history',commands:'/api/commands/:id',realtime:'/api/realtime'}));
  app.use(express.static(path.resolve(__dirname,'../../petfeeder_app/build/web')));
  app.get('/',(req,res)=>res.redirect('/api'));
  app.use((err,req,res,next)=>res.status(err.status||500).json({success:false,
    code:err instanceof SyntaxError?'INVALID_JSON':err.code||'INTERNAL_ERROR',message:err.message}));

  const server=http.createServer(app);
  const realtime=new WebSocketServer({noServer:true,handleProtocols:protocols=>
    websocketToken?'petfeeder':protocols.values().next().value});
  const peers=new Set();
  const broadcast=message=>{
    const data=JSON.stringify(message);
    for(const peer of peers)if(peer.readyState===WebSocket.OPEN)peer.send(data);
  };
  integration.setRealtimePublisher(broadcast);
  realtime.on('connection',async peer=>{
    peers.add(peer);peer.on('close',()=>peers.delete(peer));
    try { peer.send(JSON.stringify({type:'snapshot',data:await integration.device()})); }
    catch { peer.close(1011,'snapshot unavailable'); }
  });
  server.on('upgrade',(request,socket,head)=>{
    let pathname;
    try { pathname=new URL(request.url,'http://localhost').pathname; } catch { socket.destroy();return; }
    if(pathname!=='/api/realtime'){socket.destroy();return;}
    if(websocketToken){
      const protocols=(request.headers['sec-websocket-protocol']||'').split(',').map(value=>value.trim());
      if(!protocols.includes('petfeeder')||!protocols.some(value=>timingSafeEqual(websocketToken,digest(value)))){
        socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
        return;
      }
    }
    realtime.handleUpgrade(request,socket,head,peer=>realtime.emit('connection',peer,request));
  });

  const host=process.env.HOST||'0.0.0.0';
  await new Promise((resolve,reject)=>{
    server.once('error',reject);
    server.listen(config.port,host,resolve);
  });
  console.log(`PetFeeder Backend: http://${host}:${server.address().port}`);
  const stop=async()=>{
    realtime.close();
    await new Promise(resolve=>server.close(resolve));
    await integration.close();
  };
  process.once('SIGINT',()=>{void stop().finally(()=>process.exit(0));});
  process.once('SIGTERM',()=>{void stop().finally(()=>process.exit(0));});
  return {server,realtime,integration};
}
if(require.main===module)startServer().catch(e=>{console.error('PetFeeder backend startup failed:',e.message);process.exitCode=1;});
module.exports={startServer};
