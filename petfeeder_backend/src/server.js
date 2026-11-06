const express = require('express');
const cors = require('cors');
const http = require('node:http');
const path = require('node:path');
const {WebSocketServer,WebSocket} = require('ws');
const config = require('./config');

async function startServer() {
  const {createBackend} = await import('./app.mjs');
  const integration=await createBackend({brokerUrl:config.mqtt.brokerUrl,databaseUrl:process.env.DATABASE_URL,
    prefix:process.env.MQTT_TOPIC_PREFIX||'duylinh0212/petfeeder/v1'});
  const app=express();app.use(cors());app.use(express.json({limit:'32kb'}));
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
  const realtime=new WebSocketServer({noServer:true});
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
