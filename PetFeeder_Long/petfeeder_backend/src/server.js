import {createServer} from 'node:http';
import {readFileSync,existsSync,statSync} from 'node:fs';
import {resolve,sep,extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {Storage} from './storage.js';
import {Service} from './service.js';
import {DeviceSimulator} from './deviceSimulator.js';
import {mqttTransport} from './mqttClient.js';
import {Invalid,object,number} from './policy.js';
const demo=process.argv.includes('--demo'),data=process.env.DATA_DIR||fileURLToPath(new URL(`../data/${demo?'demo':'mqtt'}/`,import.meta.url));
const db=new Storage(`${data}/backend.sqlite`);let offset=0;
const clock=()=>Math.floor(Date.now()/1000)+offset;
const appRoot=process.env.APP_DIR||fileURLToPath(new URL('../../petfeeder_app/build/web/',import.meta.url));
let device,deviceDB,service;
const transport=demo?{mode:'DEMO',send(kind,payload){
  if(!device?.online)return false;
  if(kind==='sync')device.sync(payload);else if(kind==='command')device.receive(payload);return true;
}}:mqttTransport(()=>service);
service=new Service(db,transport,clock);
function boot(){device=new DeviceSimulator(deviceDB,e=>service.event(e),h=>service.heartbeat(h),clock);service.sync();device.heartbeat();}
if(demo){deviceDB=new Storage(`${data}/device.sqlite`);boot();}
const timer=setInterval(()=>{
  try{if(demo)device.tick();
    // Retry original unexpired QUEUED commands; device and API preserve the original ID.
    for(const c of db.all('commands'))if(c.status==='QUEUED'){
      if(clock()>=c.expires_at)db.put('commands',c.command_id,{...c,status:'DELIVERY_UNKNOWN',error_code:'AWAITING_DEVICE_RESULT'});
      else transport.send('command',c);
    }
  }catch(e){console.error('tick:',e);}
},1000);
async function body(req){let b='';for await(const chunk of req){b+=chunk;if(b.length>32768)throw new Invalid('BODY_TOO_LARGE');}try{return object(JSON.parse(b));}catch(e){if(e instanceof Invalid)throw e;throw new Invalid('INVALID_JSON');}}
const server=createServer(async(req,res)=>{
  res.setHeader('Access-Control-Allow-Origin',process.env.APP_ORIGIN||'*');
  res.setHeader('Access-Control-Allow-Headers','Content-Type');
  res.setHeader('Access-Control-Allow-Methods','GET,POST,OPTIONS');
  res.setHeader('Cache-Control','no-store');
  const reply=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8'});res.end(JSON.stringify(data));};
  if(req.method==='OPTIONS'){res.writeHead(204);res.end();return;}
  const path=new URL(req.url,'http://localhost').pathname;
  try{
    if(req.method==='GET'&&(path==='/debug'||path==='/debug/')){res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});res.end(readFileSync(new URL('../public/index.html',import.meta.url)));return;}
    if(req.method==='GET'&&path==='/api/state')return reply(200,service.state());
    if(req.method==='GET'&&path==='/api/history')return reply(200,{commands:db.all('commands'),events:db.all('events')});
    if(req.method==='GET'&&path==='/api/id')return reply(200,{command_id:service.id(),now:clock(),ttl_s:service.settings().command_ttl_s});
    if(req.method==='POST'){
      const b=await body(req);
      if(path==='/api/feeding')return reply(200,service.feed(b));
      if(path==='/api/config')return reply(200,service.configure(b));
      if(path==='/api/schedules')return reply(200,service.setSchedules(b.schedules));
      if(demo&&path==='/api/demo'){
        const allowed=['online','weight_g','time_valid','calibrated','auto_feed','advance_s','restart','reconcile'];
        for(const k of Object.keys(b))if(!allowed.includes(k))throw new Invalid('UNKNOWN_FIELD',k);
        for(const k of ['online','time_valid','calibrated','auto_feed','restart','reconcile'])if(k in b&&typeof b[k]!=='boolean')throw new Invalid('INVALID_FIELD',k);
        if('weight_g'in b&&b.weight_g!==null)number(b.weight_g,0,5000,'weight_g');
        if('advance_s'in b)number(b.advance_s,0,604800,'advance_s',true);
        if('online'in b)device.online=b.online;
        for(const k of ['weight_g','time_valid','calibrated','auto_feed'])if(k in b)device.sensors[k]=b[k];
        if(b.advance_s)offset+=b.advance_s;
        if(b.restart){const sensors={...device.sensors},online=device.online;boot();device.sensors=sensors;device.online=online;}
        if(b.reconcile)device.reconcile();
        device.tick();if(device.online)service.sync();return reply(200,service.state());
      }
    }
    if(req.method==='GET'&&!path.startsWith('/api/')){
      const decoded=decodeURIComponent(path),root=resolve(appRoot),file=resolve(root,'.'+(decoded==='/'?'/index.html':decoded));
      if(file!==root&&!file.startsWith(root+sep))return reply(403,{error:'FORBIDDEN'});
      if(existsSync(file)&&statSync(file).isFile()){
        const types={'.html':'text/html; charset=utf-8','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.svg':'image/svg+xml','.woff2':'font/woff2','.ttf':'font/ttf','.css':'text/css'};
        res.writeHead(200,{'Content-Type':types[extname(file)]||'application/octet-stream'});res.end(readFileSync(file));return;
      }
      if(decoded==='/'){res.writeHead(503,{'Content-Type':'text/html; charset=utf-8'});res.end('<!doctype html><html lang="vi"><meta charset="utf-8"><title>PetFeeder</title><h1>PetFeeder</h1><p>Cần build app Flutter trước: chạy flutter build web trong thư mục petfeeder_app.</p><a href="/debug">Bảng kiểm thử backend</a></html>');return;}
    }
    reply(404,{error:'NOT_FOUND'});
  }catch(e){reply(e.http||500,{error:e.code||'INTERNAL_ERROR',field:e.field||'',message:e.http?e.message:'Server error; see terminal'});if(!e.http)console.error(e);}
});
const port=Number(process.env.PORT||8080),host=process.env.HOST||'127.0.0.1';
server.listen(port,host,()=>console.log(`PetFeeder ${transport.mode}: http://${host}:${server.address().port}`));
function stop(){clearInterval(timer);server.close(()=>{transport.close?.();deviceDB?.close();db.close();process.exit(0);});}
process.on('SIGINT',stop);process.on('SIGTERM',stop);
