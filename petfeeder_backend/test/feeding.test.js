const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs"),
  os = require("os"),
  path = require("path");
const { EventEmitter } = require("events");
const directory = fs.mkdtempSync(path.join(os.tmpdir(), "petfeeder-test-"));
process.env.PETFEEDER_DB_FILE = path.join(directory, "database.json");
fs.writeFileSync(
  process.env.PETFEEDER_DB_FILE,
  JSON.stringify({
    device_state: {},
    device_config: {},
    schedules: [],
    feeding_history: [{ id: "legacy", actual_weight_g: 20, status: "SUCCESS" }],
    alerts: [],
  }),
);
const store = require("../src/storage"),
  mqtt = require("../src/mqttClient"),
  config = require("../src/config");
const published = [];
class FakeClient extends EventEmitter {
  subscribe() {}
  publish(topic, bytes, opts, callback) {
    published.push({ topic, payload: JSON.parse(bytes), opts });
    if (this.dropAck) callback(new Error("lost ack"));
    else callback?.();
  }
  end() {}
}
const client = new FakeClient();
mqtt.initMQTT(() => client);
client.emit("connect");
let server, base;
function telemetry(patch = {}) {
  mqtt.handleIncomingMessage(config.mqtt.topics.telemetry, {
    contract_version: 2,
    device_id: "petfeeder_01",
    status: "SAN SANG",
    scale_valid: true,
    ultrasonic_valid: true,
    scale_stable: true,
    bowl_presence_available: true,
    bowl_present: true,
    hopper_verified: true,
    bowl_weight_g: 0,
    distance_cm: 12,
    food_level_percent: 52,
    busy: false,
    lockdown: false,
    ...patch,
  });
}
async function api(url, body, method = "POST") {
  const r = await fetch(base + url, {
    method,
    headers: { "content-type": "application/json" },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
  return { status: r.status, body: await r.json() };
}
function event(id, status = "SUCCESS", patch = {}) {
  mqtt.handleIncomingMessage(config.mqtt.topics.events, {
    event_id: id + ":3",
    command_id: id,
    revision: 3,
    status,
    error_code: "NONE",
    target_portion_g: 30,
    root_target_g: 30,
    actual_weight_g: 30,
    cumulative_delivered_g: 30,
    measurement_valid: true,
    source: "app",
    started_at: Math.floor(Date.now() / 1000) - 10,
    completed_at: Math.floor(Date.now() / 1000),
    ...patch,
  });
}
function finishAll() {
  for (const c of store.getCommands())
    if (
      ["PUBLISHING", "ACCEPTED", "UNKNOWN", "DISPENSING", "PAUSED"].includes(
        c.status,
      )
    )
      event(c.command_id, "INTERRUPTED", {
        error_code: "TEST_RESET",
        revision: 100,
        event_id: c.command_id + ":100",
        measurement_valid: false,
        actual_weight_g: null,
      });
  telemetry();
  store.updateDeviceState({ last_feed_time: null });
}
before(async () => {
  const app = require("../src/server");
  server = await new Promise((resolve) => {
    const s = app.listen(0, "127.0.0.1", () => resolve(s));
  });
  base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => {
  mqtt.close();
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(directory, { recursive: true, force: true });
});
test("migration preserves history and makes a backup; no fake readings", () => {
  assert(fs.existsSync(process.env.PETFEEDER_DB_FILE + ".v1.bak"));
  assert.equal(store.getFeedingHistory()[0].id, "legacy");
  assert.equal(store.getDeviceState().bowl_weight_g, null);
});
test("acceptance is 202, same ID never publishes twice, changed payload conflicts", async () => {
  telemetry();
  const first = await api("/api/feeding/feed", {
    command_id: "one",
    portion: 30,
    override: false,
  });
  assert.equal(first.status, 202);
  assert.equal(first.body.data.status, "ACCEPTED");
  assert.equal(first.body.data.actual_weight_g, null);
  const count = published.length;
  assert.equal(
    (
      await api("/api/feeding/feed", {
        command_id: "one",
        portion: 30,
        override: false,
      })
    ).status,
    202,
  );
  assert.equal(published.length, count);
  assert.equal(
    (await api("/api/feeding/feed", { command_id: "one", portion: 40 })).body
      .code,
    "COMMAND_ID_CONFLICT",
  );
  finishAll();
});
test("C05 C07 C08 override cannot bypass empty, pending refill or lock", async () => {
  for (const [patch, code] of [
    [{ distance_cm: 24 }, "FOOD_EMPTY"],
    [{ hopper_verified: false }, "UNVERIFIED_FOOD"],
    [{ lockdown: true }, "SAFETY_LOCKOUT"],
  ]) {
    telemetry(patch);
    const r = await api("/api/feeding/feed", { portion: 30, override: true });
    assert.equal(r.body.code, code);
  }
  telemetry();
});
test("N01 capacity rejects without publishing", async () => {
  telemetry({ bowl_weight_g: 135 });
  const n = published.length;
  assert.equal(
    (await api("/api/feeding/feed", { portion: 30, override: true })).body.code,
    "BOWL_CAPACITY_EXCEEDED",
  );
  assert.equal(n, published.length);
  telemetry();
});
test("N03 concurrent submissions admit exactly one", async () => {
  const r = await Promise.all(
    ["concurrent-a", "concurrent-b"].map((command_id) =>
      api("/api/feeding/feed", { command_id, portion: 30 }),
    ),
  );
  assert.deepEqual(r.map((x) => x.status).sort(), [202, 409]);
  finishAll();
});
test("N04 retry references original and only its remaining amount; one child", async () => {
  event("partial", "PARTIAL", {
    actual_weight_g: 20,
    cumulative_delivered_g: 20,
    root_target_g: 50,
    target_portion_g: 50,
    error_code: "MAX_PULSES_REACHED",
  });
  store.updateDeviceState({ last_feed_time: null });
  let r = await api("/api/feeding/commands/partial/retry", {
    command_id: "retry",
    portion: 50,
  });
  assert.equal(r.status, 202);
  assert.equal(r.body.data.target_portion_g, 30);
  assert.equal(published.at(-1).payload.retry_of, "partial");
  event("retry", "SUCCESS", {
    target_portion_g: 30,
    root_target_g: 50,
    cumulative_delivered_g: 50,
  });
  store.updateDeviceState({ last_feed_time: null });
  r = await api("/api/feeding/commands/partial/retry", {
    command_id: "retry-again",
    portion: 50,
  });
  assert.equal(r.body.code, "RETRY_ALREADY_USED");
  finishAll();
});
test("N07 unknown delivery cannot be retried or shown as zero", async () => {
  event("unknown", "TIMEOUT", {
    measurement_valid: false,
    actual_weight_g: null,
    error_code: "MAX_DURATION_REACHED",
  });
  store.updateDeviceState({ last_feed_time: null });
  assert.equal(store.getCommand("unknown").actual_weight_g, null);
  assert.equal(
    (await api("/api/feeding/commands/unknown/retry", { portion: 30 })).body
      .code,
    "RECONCILIATION_REQUIRED",
  );
});
test("N09 absent sensor blocks feed; paused resume needs confirmation", async () => {
  telemetry({ bowl_presence_available: false });
  assert.equal(
    (await api("/api/feeding/feed", { portion: 30 })).body.code,
    "BOWL_PRESENCE_UNAVAILABLE",
  );
  telemetry({ busy: true, active_command_id: "paused" });
  event("paused", "PAUSED", {
    measurement_valid: false,
    actual_weight_g: null,
    cumulative_delivered_g: 10,
    error_code: "BOWL_MISSING",
  });
  store.updateDeviceState({ last_feed_time: null });
  assert.equal(
    (await api("/api/feeding/commands/paused/retry", { portion: 30 })).body
      .code,
    "RECONCILIATION_REQUIRED",
  );
  assert.equal(
    (await api("/api/feeding/commands/paused/cancel", {})).status,
    202,
  );
  finishAll();
});
test("N10 N11 invalid sensor stays null; requests blocked", async () => {
  telemetry({ scale_valid: false, bowl_weight_g: 0 });
  assert.equal(store.getDeviceState().bowl_weight_g, null);
  assert.equal(
    (await api("/api/feeding/feed", { portion: 30 })).body.code,
    "SENSOR_ERROR",
  );
  telemetry({ ultrasonic_valid: false, distance_cm: 0 });
  assert.equal(store.getDeviceState().distance_cm, null);
  telemetry();
});
test("N13 N14 bowl events use unknown cause and deduplicate", () => {
  const n = store.getAlerts().length;
  const p = {
    event: "BOWL_EVENT",
    event_id: "bowl-1",
    type: "WEIGHT_DECREASED",
    delta_g: -15,
    cause: "UNKNOWN_CAUSE",
  };
  mqtt.handleIncomingMessage(config.mqtt.topics.events, p);
  mqtt.handleIncomingMessage(config.mqtt.topics.events, p);
  assert.equal(store.getAlerts().length, n + 1);
  assert.match(store.getAlerts()[0].message, /UNKNOWN_CAUSE/);
});
test("results survive visible history deletion, duplicates and late revisions", async () => {
  event("dedup", "SENSOR_ERROR", {
    error_code: "HX711_OFFLINE",
    measurement_valid: false,
    actual_weight_g: null,
  });
  const n = store.getAlerts().length;
  event("dedup", "SENSOR_ERROR", {
    error_code: "HX711_OFFLINE",
    measurement_valid: false,
    actual_weight_g: null,
  });
  assert.equal(store.getAlerts().length, n);
  store.clearFeedingHistory();
  event("dedup", "SENSOR_ERROR", {
    error_code: "HX711_OFFLINE",
    measurement_valid: false,
    actual_weight_g: null,
  });
  assert.equal(store.getFeedingHistory().length, 0);
  assert.equal(store.getCommand("dedup").error_code, "HX711_OFFLINE");
  assert.equal(
    (await api("/api/feeding/commands/dedup", undefined, "GET")).status,
    200,
  );
});
test("invalid input rejects strings, fractions in integer config, unsafe bounds", async () => {
  finishAll();
  for (const body of [
    { portion: "30" },
    { portion: 0 },
    { portion: 30, override: "true" },
    { portion: 30, target_portion_g: 45 },
  ])
    assert.equal((await api("/api/feeding/feed", body)).status, 400);
  for (const body of [
    { max_feed_pulses: 1.5 },
    { max_duration_ms: 0 },
    { tank_height_cm: 10 },
    { lockdown: "true" },
  ])
    assert.equal((await api("/api/device/config", body, "PUT")).status, 400);
  const r = await api("/api/device/config", { lockdown: true }, "PUT");
  assert.equal(r.status, 202);
  assert.equal(published.at(-1).opts.retain, false);
});
test("lost broker ack stays unknown and repeat cannot replay physical command", async () => {
  finishAll();
  client.dropAck = true;
  const r = await api("/api/feeding/feed", { portion: 30, command_id: "lost" });
  assert.equal(r.status, 202);
  assert.equal(r.body.data.status, "UNKNOWN");
  const n = published.length;
  await api("/api/feeding/feed", { portion: 30, command_id: "lost" });
  assert.equal(n, published.length);
  client.dropAck = false;
  finishAll();
});
test("offline and stale telemetry do not accept feed", async () => {
  store.updateDeviceState({ online: true, last_seen: "2000-01-01T00:00:00Z" });
  assert.equal((await api("/api/feeding/feed", { portion: 30 })).status, 503);
  telemetry();
});

test("paused parent is closed when a confirmed child is accepted", async () => {
  finishAll();
  telemetry({ busy: true, active_command_id: "pause-parent" });
  event("pause-parent", "PAUSED", {
    measurement_valid: false,
    actual_weight_g: null,
    cumulative_delivered_g: 10,
    error_code: "BOWL_MISSING",
  });
  store.updateDeviceState({ last_feed_time: null });
  const r = await api("/api/feeding/commands/pause-parent/retry", {
    command_id: "pause-child",
    portion: 30,
    confirm_bowl: true,
  });
  assert.equal(r.status, 202);
  event("pause-child", "ACCEPTED", {
    retry_of: "pause-parent",
    target_portion_g: 20,
    measurement_valid: true,
    actual_weight_g: 0,
    completed_at: 0,
  });
  assert.equal(store.getCommand("pause-parent").status, "RESUMED");
  event("pause-child", "SUCCESS", {
    retry_of: "pause-parent",
    target_portion_g: 20,
    actual_weight_g: 20,
    cumulative_delivered_g: 30,
    revision: 4,
    event_id: "pause-child:4",
  });
  telemetry();
  store.updateDeviceState({ last_feed_time: null });
  assert.equal(
    (
      await api("/api/feeding/feed", {
        command_id: "after-resume",
        portion: 30,
      })
    ).status,
    202,
  );
  finishAll();
});
test("retained snapshots cannot make a disconnected device appear online", () => {
  store.updateDeviceState({ online: false });
  client.emit(
    "message",
    config.mqtt.topics.telemetry,
    Buffer.from(
      JSON.stringify({
        contract_version: 2,
        device_id: "petfeeder_01",
        scale_valid: true,
      }),
    ),
    { retain: true },
  );
  assert.equal(store.getDeviceState().online, false);
  telemetry();
});
test("safety lock is delivered while busy; measurement settings wait until idle", async () => {
  telemetry({ busy: true });
  assert.equal(
    (await api("/api/device/config", { max_feed_pulses: 10 }, "PUT")).status,
    409,
  );
  assert.equal(
    (await api("/api/device/config", { lockdown: true }, "PUT")).status,
    202,
  );
  assert.deepEqual(published.at(-1).payload.config, { lockdown: true });
  telemetry();
});

test("checking an unknown command queries the MCU without feeding again", async () => {
  finishAll();
  client.dropAck = true;
  await api("/api/feeding/feed", { command_id: "query-lost", portion: 30 });
  client.dropAck = false;
  const count = published.filter(
    (x) =>
      x.payload.command === "FEED" && x.payload.command_id === "query-lost",
  ).length;
  const r = await api("/api/feeding/commands/query-lost", undefined, "GET");
  assert.equal(r.body.data.status, "UNKNOWN");
  assert.equal(published.at(-1).payload.command, "QUERY");
  assert.equal(published.at(-1).payload.command_id, "query-lost");
  assert.equal(
    published.filter(
      (x) =>
        x.payload.command === "FEED" && x.payload.command_id === "query-lost",
    ).length,
    count,
  );
  event("query-lost", "SUCCESS");
  assert.equal(
    (await api("/api/feeding/commands/query-lost", undefined, "GET")).body.data
      .status,
    "SUCCESS",
  );
});

test("reported config matches MCU and old results retain their own tolerance", () => {
  telemetry({
    config_snapshot: { bowl_capacity_g: 220, portion_tolerance_g: 1 },
  });
  assert.equal(store.getDeviceConfig().bowl_capacity_g, 220);
  event("old-tolerance", "SUCCESS", {
    actual_weight_g: 34,
    portion_tolerance_g: 5,
  });
  assert.equal(store.getCommand("old-tolerance").status, "SUCCESS");
  store.updateDeviceConfig({ bowl_capacity_g: 150, portion_tolerance_g: 3 });
});
