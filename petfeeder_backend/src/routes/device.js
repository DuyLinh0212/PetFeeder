const router = require("express").Router();
const storage = require("../storage");
const mqtt = require("../mqttClient");
const { validate } = require("../deviceConfig");
router.get("/status", (req, res) => {
  const state = storage.getDeviceState(),
    cfg = storage.getDeviceConfig();
  const fresh =
    state.last_seen && Date.now() - Date.parse(state.last_seen) <= 15000;
  res.json({
    success: true,
    data: {
      ...state,
      online: !!(state.online && fresh),
      mqtt_connected: mqtt.isMQTTConnected(),
      safe_interval_sec: cfg.safe_interval_sec,
      empty_threshold_cm: cfg.empty_threshold_cm,
    },
  });
});
router.get("/config", (req, res) =>
  res.json({ success: true, data: storage.getDeviceConfig() }),
);
router.put("/config", async (req, res, next) => {
  try {
    const patch = req.body;
    if (
      !Object.keys(patch).length ||
      !validate(patch, storage.getDeviceConfig())
    )
      return res.status(400).json({
        success: false,
        code: "INVALID_CONFIG",
        message: "Cấu hình ngoài giới hạn hoặc sai kiểu.",
      });
    const state = storage.getDeviceState();
    if (
      !mqtt.isMQTTConnected() ||
      !state.online ||
      Date.now() - Date.parse(state.last_seen) > 15000
    )
      return res.status(503).json({
        success: false,
        code: "DEVICE_OFFLINE",
        message: "Thiết bị chưa trực tuyến.",
      });
    if (
      state.busy &&
      Object.keys(patch).some((k) => !["lockdown", "mark_refill"].includes(k))
    )
      return res.status(409).json({
        success: false,
        code: "DEVICE_BUSY",
        message: "Chờ phiên cho ăn kết thúc trước khi đổi cấu hình.",
      });
    if (patch.mark_refill && patch.verify_refill)
      return res.status(400).json({
        success: false,
        code: "INVALID_CONFIG",
        message: "Đánh dấu nạp hạt và xác nhận là hai thao tác riêng.",
      });
    await mqtt.syncConfigToDevice(patch);
    const { mark_refill, verify_refill, ...persistent } = patch;
    const updated = storage.updateDeviceConfig(persistent);
    res.status(202).json({
      success: true,
      data: updated,
      message: "Đã gửi. Trạng thái thiết bị sẽ cập nhật sau khi nhận cấu hình.",
    });
  } catch (e) {
    next(e);
  }
});
module.exports = router;
