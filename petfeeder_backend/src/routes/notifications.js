const express = require('express');
const router = express.Router();
const storage = require('../storage');

/**
 * GET /api/notifications
 * Lấy danh sách cảnh báo & thông báo (FR-07)
 */
router.get('/', (req, res) => {
  try {
    const alerts = storage.getAlerts();
    return res.status(200).json({
      success: true,
      count: alerts.length,
      unread_count: alerts.filter(a => !a.read).length,
      data: alerts
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * PATCH /api/notifications/:id/read
 * Đánh dấu thông báo đã đọc
 */
router.patch('/:id/read', (req, res) => {
  try {
    const { id } = req.params;
    const ok = storage.markAlertRead(id);
    if (!ok) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy thông báo' });
    }
    return res.status(200).json({
      success: true,
      message: 'Đã đánh dấu thông báo là đã đọc'
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

/**
 * DELETE /api/notifications
 * Xóa toàn bộ thông báo
 */
router.delete('/', (req, res) => {
  try {
    storage.clearAlerts();
    return res.status(200).json({
      success: true,
      message: 'Đã xóa tất cả thông báo'
    });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
