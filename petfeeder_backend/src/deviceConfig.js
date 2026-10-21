// Bounds mirror feeder::Config. Validate merged values, including related fields.
const fields = {
  bowl_capacity_g: [150, 5, 10000],
  max_daily_portion_g: [200, 5, 10000],
  portion_tolerance_g: [3, 0.01, 10],
  fine_threshold_g: [10, 0.01, 10000],
  stable_spread_g: [3, 0.01, 10],
  idle_delta_g: [5, 0.01, 100],
  interference_drop_g: [2, 0.01, 10],
  min_pulse_gain_g: [1, 0.01, 5],
  empty_threshold_cm: [20, 0.01, 400],
  tank_height_cm: [25, 0.01, 400],
  refill_jump_cm: [5, 0.01, 400],
  safe_interval_sec: [180, 0, 86400, true],
  max_duration_ms: [30000, 1000, 120000, true],
  stable_timeout_ms: [3000, 250, 10000, true],
  coarse_open_ms: [500, 50, 2000, true],
  coarse_settle_ms: [400, 50, 5000, true],
  fine_open_ms: [200, 50, 2000, true],
  fine_settle_ms: [600, 50, 5000, true],
  anti_step_ms: [150, 50, 500, true],
  sample_stale_ms: [1000, 250, 5000, true],
  max_feed_pulses: [15, 1, 100, true],
  anti_jam_max_retries: [3, 1, 5, true],
  max_daily_feeds: [6, 1, 100, true],
};
const defaults = Object.fromEntries(
  Object.entries(fields).map(([k, v]) => [k, v[0]]),
);
function validate(patch, current = defaults) {
  if (!patch || typeof patch !== "object" || Array.isArray(patch)) return false;
  for (const [key, value] of Object.entries(patch)) {
    if (["lockdown", "verify_refill", "mark_refill"].includes(key)) {
      if (typeof value !== "boolean") return false;
    } else {
      const spec = fields[key];
      if (
        !spec ||
        typeof value !== "number" ||
        !Number.isFinite(value) ||
        value < spec[1] ||
        value > spec[2] ||
        (spec[3] && !Number.isInteger(value))
      )
        return false;
    }
  }
  const cfg = { ...current, ...patch };
  return (
    cfg.empty_threshold_cm <= cfg.tank_height_cm &&
    cfg.refill_jump_cm <= cfg.tank_height_cm &&
    cfg.fine_threshold_g <= cfg.bowl_capacity_g
  );
}
module.exports = { defaults, fields, validate };
