export const defaults = Object.freeze({
  max_portion_g: 100, daily_limit_g: 200, min_interval_s: 180,
  command_ttl_s: 60,
  feed_timeout_s: 30, tolerance_g: 2, timezone_offset_min: 420,
  require_pet: false,
  bowl_capacity_g: 150, max_daily_feeds: 6, max_feed_pulses: 15,
  coarse_fine_threshold_g: 10,
  pulse_step_angle: 90, pulse_step_ms: 600,
});
export const terminal = new Set(['SUCCESS', 'PARTIAL', 'INTERRUPTED', 'REJECTED',
  'COMMAND_EXPIRED', 'SENSOR_ERROR', 'BOWL_MISSING', 'TIMEOUT', 'OVER_PORTION']);
export const dispensedStatuses = new Set(['SUCCESS','HOAN TAT','PARTIAL','OVER_PORTION','SENSOR_ERROR','INTERRUPTED','TIMEOUT']);
export class Invalid extends Error {
  constructor(code, field = '') { super(`${code}${field ? ': ' + field : ''}`); this.code = code; this.field = field; this.http = 400; }
}
export function number(v, min, max, field, integer = false) {
  if (typeof v !== 'number' || !Number.isFinite(v) || v < min || v > max || (integer && !Number.isInteger(v))) throw new Invalid('INVALID_FIELD', field);
  return v;
}
export function identifier(v, field) {
  if (typeof v !== 'string' || !/^[A-Za-z0-9_.:-]{1,96}$/.test(v)) throw new Invalid('INVALID_FIELD', field);
  return v;
}
export function object(v) { if (!v || typeof v !== 'object' || Array.isArray(v)) throw new Invalid('INVALID_OBJECT'); return v; }
export function config(input) {
  object(input);
  const bounds = {max_portion_g:[1,500],daily_limit_g:[1,2000],min_interval_s:[1,86400],
    command_ttl_s:[5,300],
    feed_timeout_s:[5,120],tolerance_g:[0.1,10],timezone_offset_min:[-720,840],
    bowl_capacity_g:[1,5000],max_daily_feeds:[1,100],max_feed_pulses:[1,100],
    coarse_fine_threshold_g:[1,100],
    pulse_step_angle:[1,180],pulse_step_ms:[100,2000]};
  for (const [k,v] of Object.entries(input)) {
    if (bounds[k]) number(v,...bounds[k],k,k!=='tolerance_g');
    else if (k==='require_pet') { if(typeof v!=='boolean') throw new Invalid('INVALID_FIELD', k); }
    else throw new Invalid('UNKNOWN_FIELD',k);
  }
  if(input.max_portion_g>input.daily_limit_g || input.tolerance_g>=input.max_portion_g) throw new Invalid('INVALID_CONFIG');
  return input;
}
export function command(c, cfg, now, checkExpiry=true) {
  object(c);
  const allowed=new Set(['command_id','source','target_portion_g','created_at','expires_at','pet_id','recognition_id','recognition_expires_at','recognition_source','confidence']);
  for(const key of Object.keys(c))if(!allowed.has(key))throw new Invalid('UNKNOWN_FIELD',key);
  identifier(c.command_id,'command_id');
  if(!['APP','BUTTON','SCHEDULE'].includes(c.source)) throw new Invalid('INVALID_FIELD','source');
  number(c.target_portion_g,1,cfg.max_portion_g,'target_portion_g');
  number(c.created_at,1700000000,4102444800,'created_at',true);
  number(c.expires_at,1700000000,4102444800,'expires_at',true);
  if(c.expires_at<=c.created_at || c.expires_at-c.created_at>300 || c.created_at>now+10) throw new Invalid('INVALID_TIME');
  if(checkExpiry && now>=c.expires_at) throw new Invalid('COMMAND_EXPIRED');
  const evidenceKeys=['pet_id','recognition_id','recognition_expires_at','recognition_source','confidence'];
  const hasEvidence=evidenceKeys.some(key=>c[key]!==undefined);
  if(hasEvidence){
    for(const key of evidenceKeys)if(c[key]===undefined)throw new Invalid('INVALID_FIELD',key);
    identifier(c.pet_id,'pet_id');identifier(c.recognition_id,'recognition_id');
    number(c.recognition_expires_at,now,now+5,'recognition_expires_at',true);
    if(c.recognition_source!=='YOLO_PET_PRESENCE')throw new Invalid('INVALID_FIELD','recognition_source');
    number(c.confidence,0.5,1,'confidence');
  }
  return c;
}
export function schedules(items,cfg) {
  if(!Array.isArray(items)||items.length>10) throw new Invalid('INVALID_SCHEDULES');
  const seen=new Set();
  for(const s of items) {
    object(s);identifier(s.schedule_id,'schedule_id');
    if(seen.has(s.schedule_id)) throw new Invalid('DUPLICATE_SCHEDULE'); seen.add(s.schedule_id);
    number(s.hour,0,23,'hour',true);number(s.minute,0,59,'minute',true);
    number(s.target_portion_g,1,cfg.max_portion_g,'target_portion_g');
    if(typeof s.enabled!=='boolean'||!Array.isArray(s.days)||s.days.length===0||s.days.length>7||new Set(s.days).size!==s.days.length) throw new Invalid('INVALID_FIELD','days/enabled');
    for(const d of s.days) number(d,0,6,'days',true);
  }
  return items;
}
export function dayKey(epoch, offset=420) { return new Date((epoch+offset*60)*1000).toISOString().slice(0,10); }
export function sameCommand(a,b) { return ['command_id','source','target_portion_g','created_at','expires_at'].every(k=>a[k]===b[k]); }
