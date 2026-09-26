require('dotenv').config();

module.exports = {
  port: parseInt(process.env.PORT || '3000', 10),
  mqtt: {
    brokerUrl: process.env.MQTT_BROKER_URL || 'mqtt://127.0.0.1:1883',
    topics: {
      command: 'petfeeder/command',
      schedulesSync: 'petfeeder/schedules/sync',
      config: 'petfeeder/config',
      telemetry: 'petfeeder/telemetry',
      events: 'petfeeder/events',
      alerts: 'petfeeder/alerts'
    }
  },
  device: {
    id: process.env.DEVICE_ID || 'petfeeder_01',
    safeIntervalSec: parseInt(process.env.SAFE_FEED_INTERVAL_SEC || '180', 10),
    tankHeightCm: parseFloat(process.env.TANK_HEIGHT_CM || '25.0'),
    emptyThresholdCm: parseFloat(process.env.EMPTY_THRESHOLD_CM || '20.0')
  }
};
