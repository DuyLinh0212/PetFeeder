import mqtt from 'mqtt';
export function mqttTransport(serviceGetter){
  const id=process.env.DEVICE_ID||'long-petfeeder-20261020-7bf19c';
  const root=`petfeeder/${id}`,url=process.env.MQTT_URL||'mqtt://127.0.0.1:1883';
  const client=mqtt.connect(url,{clientId:`backend-${id}`,clean:true,reconnectPeriod:3000,
    username:process.env.MQTT_USERNAME,password:process.env.MQTT_PASSWORD});
  client.on('connect',()=>{console.log('MQTT connected',root);client.subscribe([`${root}/event`,`${root}/telemetry`],{qos:1},()=>serviceGetter().sync());});
  client.on('error',e=>console.error('MQTT:',e.message));
  client.on('message',(topic,body,packet)=>{try{
    const data=JSON.parse(body.toString());
    if(topic===`${root}/event`){
      // Events are never retained. Replay via device's acknowledged persistent outbox instead.
      if(packet.retain)return;
      serviceGetter().event(data);
      client.publish(`${root}/ack`,JSON.stringify({event_id:data.event_id}),{qos:1,retain:false});
    }else if(!packet.retain){serviceGetter().heartbeat(data);}
  }catch(e){console.error('MQTT rejected:',e.message);}});
  return {mode:'MQTT',send(kind,body){
    if(!client.connected)return false;
    client.publish(`${root}/${kind}`,JSON.stringify(body),{qos:1,retain:false});return true;
  },close(){client.end();}};
}
