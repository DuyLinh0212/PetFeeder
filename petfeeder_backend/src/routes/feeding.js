const express = require("express");
const { randomUUID } = require("crypto");
const router = express.Router();
const storage = require("../storage");
const mqtt = require("../mqttClient");
const pending = (s) =>
  ["PUBLISHING", "ACCEPTED", "DISPENSING", "PAUSED", "UNKNOWN"].includes(s);
const fail = (res, code, message, status = 409) =>
  res.status(status).json({ success: false, code, message });
function connected(res) {
  const s = storage.getDeviceState();
  if (
    !mqtt.isMQTTConnected() ||
    !s.online ||
    !s.last_seen ||
    Date.now() - Date.parse(s.last_seen) > 15000
  ) {
    fail(res, "DEVICE_OFFLINE", "Thiết bị chưa trực tuyến.", 503);
    return null;
  }
  if (s.contract_version !== 2) {
    fail(
      res,
      "FIRMWARE_UPDATE_REQUIRED",
      "Cần cập nhật firmware trước khi cấp hạt.",
      409,
    );
    return null;
  }
  return s;
}
async function submit(req, res, parent = null) {
  const body = req.body;
  const portion = body.target_portion_g ?? body.portion;
  const id = body.command_id ?? randomUUID();
  if (
    typeof id !== "string" ||
    !/^[a-zA-Z0-9_-]{1,64}$/.test(id) ||
    typeof portion !== "number" ||
    !Number.isFinite(portion) ||
    portion < 5 ||
    portion > 300 ||
    (body.portion !== undefined &&
      body.target_portion_g !== undefined &&
      body.portion !== body.target_portion_g) ||
    (body.override !== undefined && typeof body.override !== "boolean") ||
    (body.confirm_bowl !== undefined && typeof body.confirm_bowl !== "boolean")
  )
    return fail(
      res,
      "INVALID_COMMAND",
      "Khẩu phần phải là số từ 5 đến 300 g; các tùy chọn phải đúng kiểu.",
      400,
    );
  const signature = JSON.stringify({
    portion,
    override: body.override === true,
    retry_of: parent?.command_id || "",
    confirm_bowl: body.confirm_bowl === true,
  });
  const old = storage.getCommand(id);
  if (old) {
    if (old.request_signature !== signature)
      return fail(
        res,
        "COMMAND_ID_CONFLICT",
        "Mã lệnh đã được dùng với nội dung khác.",
      );
    return res
      .status(202)
      .json({ success: true, data: old, message: "Trạng thái lệnh đã có." });
  }
  const s = connected(res);
  if (!s) return;
  if (s.lockdown)
    return fail(res, "SAFETY_LOCKOUT", "Thiết bị đang khóa an toàn.");
  if (!s.hopper_verified || s.lid_open)
    return fail(
      res,
      "UNVERIFIED_FOOD",
      "Hãy kiểm tra và xác nhận hộp hạt trong Cài đặt.",
    );
  if (!s.scale_valid || !s.ultrasonic_valid)
    return fail(res, "SENSOR_ERROR", "Cảm biến chưa có số đo hợp lệ.");
  if (!s.bowl_presence_available)
    return fail(
      res,
      "BOWL_PRESENCE_UNAVAILABLE",
      "Chưa có cảm biến hiện diện bát.",
    );
  if (!s.bowl_present)
    return fail(res, "BOWL_MISSING", "Hãy đặt lại bát thức ăn.");
  const cfg = storage.getDeviceConfig();
  if (s.distance_cm >= cfg.empty_threshold_cm)
    return fail(res, "FOOD_EMPTY", "Hộp chứa đã hết hạt.");
  const resume =
    parent?.status === "PAUSED" && s.active_command_id === parent.command_id;
  if (
    (s.busy && !resume) ||
    storage
      .getCommands()
      .some(
        (c) =>
          pending(c.status) &&
          c.command_id !== (resume ? parent.command_id : null),
      )
  )
    return fail(
      res,
      "DEVICE_BUSY",
      "Đang có phiên cho ăn cần hoàn tất hoặc kiểm tra.",
    );
  let target = portion;
  if (parent) {
    if (!["JAM_ERROR", "PARTIAL", "TIMEOUT", "PAUSED"].includes(parent.status))
      return fail(res, "RETRY_NOT_ALLOWED", "Phiên này không thể cấp tiếp.");
    if (
      storage
        .getCommands()
        .some(
          (c) => c.retry_of === parent.command_id && c.status !== "REJECTED",
        )
    )
      return fail(
        res,
        "RETRY_ALREADY_USED",
        "Phiên này đã có yêu cầu cấp tiếp.",
      );
    if (!parent.measurement_valid && !(resume && body.confirm_bowl === true))
      return fail(
        res,
        "RECONCILIATION_REQUIRED",
        "Chưa xác định được lượng đã cấp; hãy kiểm tra thiết bị.",
      );
    target = parent.root_target_g - parent.cumulative_delivered_g;
    if (!Number.isFinite(target) || target <= cfg.portion_tolerance_g)
      return fail(res, "NOTHING_TO_RETRY", "Không còn lượng cần cấp tiếp.");
  }
  if (s.bowl_weight_g + target > cfg.bowl_capacity_g)
    return fail(
      res,
      "BOWL_CAPACITY_EXCEEDED",
      "Bát không đủ chỗ cho khẩu phần này.",
    );
  if (
    body.override !== true &&
    s.last_feed_time &&
    Date.now() - Date.parse(s.last_feed_time) < cfg.safe_interval_sec * 1000
  )
    return fail(
      res,
      "BLOCKED_DUPLICATE",
      "Bữa trước vừa được cấp. Chờ đủ thời gian hoặc xác nhận cho ăn thêm.",
    );
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    command_id: id,
    command: parent ? "RETRY" : "FEED",
    source: "app",
    target_portion_g: portion,
    override: body.override === true,
    retry_of: parent?.command_id || "",
    confirm_bowl: body.confirm_bowl === true,
    created_at: now,
    expires_at: now + 60,
  };
  storage.createCommand({
    ...payload,
    request_signature: signature,
    status: "PUBLISHING",
    actual_weight_g: null,
    measurement_valid: false,
    target_portion_g: target,
  });
  try {
    await mqtt.publishFeedCommand(payload);
    const command = storage.getCommand(id);
    // A device event can arrive before the MQTT acknowledgement.
    if (command.status === "PUBLISHING")
      storage.updateCommand(id, { status: "ACCEPTED" });
    return res.status(202).json({
      success: true,
      data: storage.getCommand(id),
      message: "Đã tiếp nhận; đang chờ kết quả từ thiết bị.",
    });
  } catch (error) {
    const command = storage.getCommand(id);
    if (command.status === "PUBLISHING")
      storage.updateCommand(id, {
        status: "UNKNOWN",
        error_code: "DELIVERY_UNCONFIRMED",
      });
    return res.status(202).json({
      success: true,
      data: storage.getCommand(id),
      message: "Chưa xác nhận được việc gửi. Kiểm tra lại cùng mã lệnh.",
    });
  }
}
router.post("/feed", (req, res, next) => submit(req, res).catch(next));
const lastQuery = new Map();
router.get("/commands/:id", async (req, res, next) => {
  try {
    let c = storage.getCommand(req.params.id);
    if (!c) return fail(res, "COMMAND_NOT_FOUND", "Chưa tìm thấy lệnh.", 404);
    if (
      pending(c.status) &&
      mqtt.isMQTTConnected() &&
      Date.now() - (lastQuery.get(c.command_id) || 0) >= 3000
    ) {
      lastQuery.set(c.command_id, Date.now());
      if (lastQuery.size > 1000)
        lastQuery.delete(lastQuery.keys().next().value);
      // QUERY can replay a cached result or expire a never-received ID. It cannot dispense.
      await mqtt
        .publishFeedCommand({
          command: "QUERY",
          command_id: c.command_id,
          target_portion_g: c.target_portion_g,
          expires_at: c.expires_at,
        })
        .catch(() => {});
      c = storage.getCommand(c.command_id);
    }
    res.json({ success: true, data: c });
  } catch (error) {
    next(error);
  }
});
router.post("/commands/:id/retry", (req, res, next) => {
  const p = storage.getCommand(req.params.id);
  if (!p) return fail(res, "RETRY_NOT_FOUND", "Không tìm thấy phiên gốc.", 404);
  submit(req, res, p).catch(next);
});
router.post("/commands/:id/cancel", async (req, res, next) => {
  try {
    const p = storage.getCommand(req.params.id);
    if (p?.status !== "PAUSED")
      return fail(
        res,
        "CANCEL_NOT_ALLOWED",
        "Chỉ hủy được phiên đang chờ đặt lại bát.",
      );
    if (!connected(res)) return;
    await mqtt.publishFeedCommand({
      command: "CANCEL",
      command_id: p.command_id,
    });
    res.status(202).json({
      success: true,
      data: p,
      message: "Đang chờ thiết bị xác nhận hủy.",
    });
  } catch (e) {
    next(e);
  }
});
router.get("/history", (req, res) =>
  res.json({
    success: true,
    data: storage.getFeedingHistory(
      Math.max(1, Math.min(200, Number(req.query.limit) || 50)),
    ),
  }),
);
router.delete("/history", (req, res) => {
  storage.clearFeedingHistory();
  res.json({ success: true, message: "Đã xóa nhật ký." });
});
module.exports = router;
