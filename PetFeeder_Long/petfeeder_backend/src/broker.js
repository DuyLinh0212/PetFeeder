import aedes from 'aedes';
import {createServer} from 'node:net';
const broker=aedes();
const server=createServer(broker.handle);
server.listen(Number(process.env.MQTT_PORT||1883),process.env.MQTT_BIND||'127.0.0.1',()=>console.log('Local MQTT broker: mqtt://127.0.0.1:1883 (demo only)'));
function stop(){server.close();broker.close(()=>process.exit(0));}
process.on('SIGINT',stop);process.on('SIGTERM',stop);
