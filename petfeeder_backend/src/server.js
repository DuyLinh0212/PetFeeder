const express = require('express');
const cors = require('cors');
const path = require('node:path');
const config = require('./config');

async function startServer() {
  const {createBackend} = await import('./app.mjs');
  const integration=createBackend({brokerUrl:config.mqtt.brokerUrl,prefix:process.env.MQTT_TOPIC_PREFIX||'duylinh0212/petfeeder/v1'});
  const app=express();app.use(cors());app.use(express.json({limit:'32kb'}));
  app.use('/api',integration.router);
  app.get('/health',(req,res)=>res.json({status:'OK',mqtt_connected:integration.connected()}));
  app.get('/api',(req,res)=>res.json({name:'PetFeeder Backend',device:'/api/device/status',schedules:'/api/schedules',feeding:'/api/feeding/feed',commands:'/api/commands/:id'}));
  app.use(express.static(path.resolve(__dirname,'../../petfeeder_app/build/web')));
  app.get('/',(req,res)=>res.redirect('/api'));
  app.use((err,req,res,next)=>res.status(err.status||500).json({success:false,code:err instanceof SyntaxError?'INVALID_JSON':'INTERNAL_ERROR',message:err.message}));
  const server=app.listen(config.port,process.env.HOST||'127.0.0.1',()=>console.log(`PetFeeder Backend: http://${process.env.HOST||'127.0.0.1'}:${server.address().port}`));
  const stop=()=>{server.close();integration.close();};
  process.once('SIGINT',()=>{stop();process.exit(0);});
  process.once('SIGTERM',()=>{stop();process.exit(0);});
  return {server,integration};
}
if(require.main===module)startServer().catch(e=>{console.error(e);process.exitCode=1;});
module.exports={startServer};
