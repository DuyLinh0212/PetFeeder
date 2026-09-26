const express = require('express');
const router = express.Router();
const storage = require('../storage');
const mqttClient = require('../mqttClient');

/**
 * POST /api/feeding/feed
 * Kích hoạt lệnh cho ăn ngay từ Mobile App (FR-08)
 * Body: { portion: number, override: boolean }
 */
router.post('/feed', (req, res) => {
  try {
    let portion = parseInt(req.body.portion || '30', 10);
    const override = !!req.body.override;

    if (isNaN(portion) || portion < 5 || portion > 300) {
      return res.status(400).json({
        success: false,
        message: 'Khẩu phần không hợp lệ (từ 5g đến 300g)'
      });
    }

    const deviceState = storage.getDeviceState();
    const deviceConfig = storage.getDeviceConfig();

    // Thuật toán kiểm tra chống cho ăn trùng (Duplicate Feed Protection - Section 2.3.2)
    if (!override && deviceState.last_feed_time) {
      const lastFeedMs = new Date(deviceState.last_feed_time).getTime();
      const elapsedSec = Math.floor((Date.now() - lastFeedMs) / 1000);
      const safeInterval = deviceConfig.safe_interval_sec || 180;

      if (elapsedSec < safeInterval) {
        const remaining = safeInterval - elapsedSec;
        return res.status(409).json({
          success: false,
          code: 'BLOCKED_DUPLICATE',
          message: `Vừa mới cho ăn cách đây ${elapsedSec}s (ngưỡng an toàn ${safeInterval}s). Vui lòng đợi ${remaining}s hoặc bật tính năng "Ghi đè" (Override) để ép cho ăn.`,
          elapsed_sec: elapsedSec,
          remaining_sec: remaining
        });
      }
    }

    // Kiểm tra mức thức ăn nếu không phải override (FR-05)
    if (!override && deviceState.distance_cm >= deviceConfig.empty_threshold_cm) {
      return res.status(400).json({
        success: false,
        code: 'FOOD_EMPTY',
        message: 'Hộp chứa đã hết thức ăn! Vui lòng nạp thêm thức ăn trước khi cho ăn.'
      });
    }

    // Gửi lệnh qua MQTT xuống ESP32
    const cmdPayload = mqttClient.publishFeedCommand({
      portion,
      override,
      source: 'app'
    });

    // Cập nhật trạng thái tạm thời
    storage.updateDeviceState({
      system_status: override ? "OVERRIDE FEED" : "DANG CHO AN..."
    });

    return res.status(200).json({
      success: true,
      message: override ? 'Đã gửi lệnh cho ăn cưỡng bức (Override)!' : 'Đã gửi lệnh cho ăn thành công!',
      data: {
        portion_g: portion,
        override: override,
        timestamp: new Date().toISOString(),
        device_status: storage.getDeviceState()
      }
    });
  } catch (err) {
    console.error('Error handling feed request:', err);
    return res.status(500).json({
      success: false,
      message: 'Lỗi máy chủ khi xử lý yêu cầu cho ăn: ' + err.message
    });
  }
});

/**
 * GET /api/feeding/history
 * Lấy danh sách lịch sử các lần cho ăn (FR-10)
 */
router.get('/history', (req, res) => {
  try {
    const limit = parseInt(req.query.limit || '50', 10);
    const history = storage.getFeedingHistory(limit);
    return res.status(200).json({
      success: true,
      count: history.length,
      data: history
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      message: err.message
    });
  }
});

/**
 * DELETE /api/feeding/history
 * Xoá toàn bộ lịch sử cho ăn
 */
router.delete('/history', (req, res) => {
  try {
    storage.clearFeedingHistory();
    return res.status(200).json({
      success: true,
      message: 'Đã xoá toàn bộ nhật ký cho ăn'
    });
  } catch (err) {
    return res.status(500).json({
      success: false,
      message: err.message
    });
  }
});

module.exports = router;
