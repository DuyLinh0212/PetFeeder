require('dotenv').config();

const mqttTopicPrefix = process.env.MQTT_TOPIC_PREFIX || 'duylinh0212/petfeeder/v1';

module.exports = {
  port: parseInt(process.env.PORT || '3000', 10),
  mqtt: {
    brokerUrl: process.env.MQTT_BROKER_URL || 'mqtt://broker.emqx.io:1883',
    topics: {
      command: `${mqttTopicPrefix}/command`,
      schedulesSync: `${mqttTopicPrefix}/schedules/sync`,
      config: `${mqttTopicPrefix}/config`,
      telemetry: `${mqttTopicPrefix}/telemetry`,
      events: `${mqttTopicPrefix}/events`,
      alerts: `${mqttTopicPrefix}/alerts`
    }
  },
  device: {
    id: process.env.DEVICE_ID || 'petfeeder_01',
    safeIntervalSec: parseInt(process.env.SAFE_FEED_INTERVAL_SEC || '180', 10),
    tankHeightCm: parseFloat(process.env.TANK_HEIGHT_CM || '25.0'),
    emptyThresholdCm: parseFloat(process.env.EMPTY_THRESHOLD_CM || '20.0')
  }
};
