const express = require('express');
const router = express.Router();
const storage = require('../storage');
const mqttClient = require('../mqttClient');

/**
 * GET /api/device/status
 * Lấy trạng thái thời gian thực của thiết bị (FR-05, FR-06)
 */
router.get('/status', (req, res) => {
  try {
    const state = storage.getDeviceState();
    const config = storage.getDeviceConfig();

    return res.status(200).json({
      success: true,
      data: {
        ...state,
        mqtt_connected: mqttClient.isMQTTConnected(),
        safe_interval_sec: config.safe_interval_sec,
        empty_threshold_cm: config.empty_threshold_cm
      }
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * GET /api/device/config
 * Lấy cấu hình thiết bị
 */
router.get('/config', (req, res) => {
  try {
    const config = storage.getDeviceConfig();
    return res.status(200).json({
      success: true,
      data: config
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * PUT /api/device/config
 * Cập nhật cấu hình thiết bị và đồng bộ xuống ESP32
 */
router.put('/config', (req, res) => {
  try {
    const patch = req.body;
    const updated = storage.updateDeviceConfig(patch);

    // Đồng bộ cấu hình xuống ESP32 qua MQTT
    mqttClient.syncConfigToDevice();

    return res.status(200).json({
      success: true,
      message: 'Cập nhật cấu hình thành công',
      data: updated
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
