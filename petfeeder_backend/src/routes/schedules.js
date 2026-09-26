const express = require('express');
const router = express.Router();
const storage = require('../storage');
const mqttClient = require('../mqttClient');

/**
 * GET /api/schedules
 * Lấy danh sách lịch cho ăn (FR-01, FR-02)
 */
router.get('/', (req, res) => {
  try {
    const schedules = storage.getSchedules();
    return res.status(200).json({
      success: true,
      count: schedules.length,
      data: schedules
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * POST /api/schedules
 * Tạo lịch cho ăn mới
 * Body: { name, time, portion_g, days, enabled }
 */
router.post('/', (req, res) => {
  try {
    const { name, time, portion_g, days, enabled } = req.body;

    if (!time || !/^\d{2}:\d{2}$/.test(time)) {
      return res.status(400).json({
        success: false,
        message: 'Thời gian không hợp lệ. Định dạng yêu cầu là HH:mm (ví dụ: 07:30)'
      });
    }

    const portion = parseInt(portion_g || '30', 10);
    if (isNaN(portion) || portion < 5 || portion > 200) {
      return res.status(400).json({
        success: false,
        message: 'Khẩu phần không hợp lệ (5g - 200g)'
      });
    }

    const newSch = storage.addSchedule({
      name: name || `Bữa ăn lúc ${time}`,
      time,
      portion_g: portion,
      days: Array.isArray(days) ? days : ["T2", "T3", "T4", "T5", "T6", "T7", "CN"],
      enabled: enabled !== undefined ? !!enabled : true
    });

    // Đồng bộ ngay danh sách lịch xuống ESP32 qua MQTT (FR-04)
    mqttClient.syncSchedulesToDevice();

    return res.status(201).json({
      success: true,
      message: 'Tạo lịch cho ăn thành công và đã đồng bộ với ESP32',
      data: newSch
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * PUT /api/schedules/:id
 * Cập nhật thông tin lịch
 */
router.put('/:id', (req, res) => {
  try {
    const { id } = req.params;
    const { name, time, portion_g, days, enabled } = req.body;

    const patch = {};
    if (name !== undefined) patch.name = name;
    if (time !== undefined) {
      if (!/^\d{2}:\d{2}$/.test(time)) {
        return res.status(400).json({ success: false, message: 'Định dạng giờ phải là HH:mm' });
      }
      patch.time = time;
    }
    if (portion_g !== undefined) patch.portion_g = parseInt(portion_g, 10);
    if (days !== undefined && Array.isArray(days)) patch.days = days;
    if (enabled !== undefined) patch.enabled = !!enabled;

    const updated = storage.updateSchedule(id, patch);
    if (!updated) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy lịch' });
    }

    // Đồng bộ lại với ESP32
    mqttClient.syncSchedulesToDevice();

    return res.status(200).json({
      success: true,
      message: 'Cập nhật lịch thành công',
      data: updated
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * PATCH /api/schedules/:id/toggle
 * Bật / Tắt kích hoạt một lịch
 */
router.patch('/:id/toggle', (req, res) => {
  try {
    const { id } = req.params;
    const schedules = storage.getSchedules();
    const target = schedules.find(s => s.id === id);

    if (!target) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy lịch' });
    }

    const updated = storage.updateSchedule(id, { enabled: !target.enabled });
    mqttClient.syncSchedulesToDevice();

    return res.status(200).json({
      success: true,
      message: `Đã ${updated.enabled ? 'bật' : 'tắt'} lịch cho ăn`,
      data: updated
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * DELETE /api/schedules/:id
 * Xóa một lịch cho ăn
 */
router.delete('/:id', (req, res) => {
  try {
    const { id } = req.params;
    const ok = storage.deleteSchedule(id);
    if (!ok) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy lịch để xóa' });
    }

    mqttClient.syncSchedulesToDevice();

    return res.status(200).json({
      success: true,
      message: 'Xóa lịch cho ăn thành công'
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
