require('dotenv').config();

const mqttTopicPrefix = process.env.MQTT_TOPIC_PREFIX || 'duylinh0212/petfeeder/v1';

module.exports = {
  port: parseInt(process.env.PORT || '3000', 10),
  mqtt: {
    brokerUrl: process.env.MQTT_BROKER_URL || 'mqtt://broker.emqx.io:1883',
    topics: {
      command: `${mqttTopicPrefix}/command`,
      sync: `${mqttTopicPrefix}/sync`,
      telemetry: `${mqttTopicPrefix}/telemetry`,
      events: `${mqttTopicPrefix}/events`,
      ack: `${mqttTopicPrefix}/ack`
    }
  },
};
