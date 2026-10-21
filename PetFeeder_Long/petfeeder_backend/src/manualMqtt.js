// A manual MQTT publisher, not an automatic test runner. Read payload JSON from stdin.
import mqtt from 'mqtt';
const [kind,repeatText,...flags]=process.argv.slice(2);
if(kind==='--help'){
  console.log('JSON stdin | node src/manualMqtt.js <command|event> <repeat:1..10> [--retain]');
  console.log('MQTT_URL defaults to mqtt://127.0.0.1:1883; DEVICE_ID chooses topic. --retain is events only.');
  process.exit(0);
}
const repeat=Number(repeatText||1),retain=flags.includes('--retain');
if(!['command','event'].includes(kind)||!Number.isInteger(repeat)||repeat<1||repeat>10||flags.some(f=>f!=='--retain')||(retain&&kind!=='event'))throw Error('Invalid arguments; use --help');
let input='';for await(const chunk of process.stdin){input+=chunk;if(input.length>32768)throw Error('Payload too large');}
const body=JSON.parse(input.replace(/^\uFEFF/,''));
if(!body||typeof body!=='object'||Array.isArray(body))throw Error('Payload must be a JSON object');
const root=`petfeeder/${process.env.DEVICE_ID||'long-petfeeder-20261020-7bf19c'}`;
const client=mqtt.connect(process.env.MQTT_URL||'mqtt://127.0.0.1:1883',{
  clean:true,reconnectPeriod:0,connectTimeout:5000,
  username:process.env.MQTT_USERNAME,password:process.env.MQTT_PASSWORD,
});
const timer=setTimeout(()=>{console.error('MQTT timeout');client.end(true);process.exitCode=1;},8000);
client.on('error',e=>{console.error(e.message);clearTimeout(timer);client.end(true);process.exitCode=1;});
client.on('connect',async()=>{
  try{
    for(let i=0;i<repeat;i++)await new Promise((ok,fail)=>client.publish(`${root}/${kind}`,JSON.stringify(body),{qos:1,retain},e=>e?fail(e):ok()));
    console.log(JSON.stringify({published:repeat,topic:`${root}/${kind}`,retain}));
  }catch(e){console.error(e.message);process.exitCode=1;}
  finally{clearTimeout(timer);client.end();}
});
