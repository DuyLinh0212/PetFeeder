const mqtt = require('mqtt');
const config = require('./src/config');
const client = mqtt.connect(config.mqtt.brokerUrl);

client.on('connect', () => {
  console.log('Test simulator connected to Mosquitto');
  const telemetry = {
    device_id: 'petfeeder_01',
    food_level_percent: 78,
    distance_cm: 6.5,
    bowl_weight_g: 42.0,
    status: 'SAN SANG',
    ip: '192.168.1.105',
    rssi: -55,
    uptime: 120
  };
  client.publish(config.mqtt.topics.telemetry, JSON.stringify(telemetry), () => {
    console.log(`Published telemetry to ${config.mqtt.topics.telemetry}`);
    const feedEvent = {
      event: 'FEED_RESULT',
      status: 'SUCCESS',
      trigger_source: 'app',
      target_portion: 40,
      actual_weight: 41.2,
      timestamp: Math.floor(Date.now() / 1000),
      message: 'Cấp thức ăn thành công (Closed-loop 41.2g)'
    };
    client.publish(config.mqtt.topics.events, JSON.stringify(feedEvent), () => {
      console.log(`Published event to ${config.mqtt.topics.events}`);
      setTimeout(() => {
        client.end();
        process.exit(0);
      }, 500);
    });
  });
});
