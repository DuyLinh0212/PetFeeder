export const defaults = Object.freeze({
  max_portion_g: 100, daily_limit_g: 200, min_interval_s: 180,
  observation_s: 60, food_stale_s: 3600, command_ttl_s: 60,
  feed_timeout_s: 30, tolerance_g: 2, timezone_offset_min: 420,
  require_pet: false, food_confirmed: false, food_label: '',
});
export const terminal = new Set(['SUCCESS', 'PARTIAL', 'INTERRUPTED', 'REJECTED',
  'COMMAND_EXPIRED', 'SENSOR_ERROR', 'JAM_ERROR', 'FOOD_EMPTY', 'TIMEOUT', 'OVER_PORTION']);
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
    observation_s:[5,86400],food_stale_s:[5,604800],command_ttl_s:[5,300],
    feed_timeout_s:[5,120],tolerance_g:[0.1,10],timezone_offset_min:[-720,840]};
  for (const [k,v] of Object.entries(input)) {
    if (bounds[k]) number(v,...bounds[k],k,k!=='tolerance_g');
    else if (k==='require_pet' || k==='food_confirmed') { if(typeof v!=='boolean') throw new Invalid('INVALID_FIELD', k); }
    else if(k==='food_label') { if(typeof v!=='string'||v.length>80) throw new Invalid('INVALID_FIELD',k); }
    else throw new Invalid('UNKNOWN_FIELD',k);
  }
  if(input.max_portion_g>input.daily_limit_g || input.tolerance_g>=input.max_portion_g) throw new Invalid('INVALID_CONFIG');
  if(input.food_confirmed && !input.food_label.trim()) throw new Invalid('FOOD_LABEL_REQUIRED');
  return input;
}
export function command(c, cfg, now, checkExpiry=true) {
  object(c); identifier(c.command_id,'command_id');
  if(!['APP','BUTTON','SCHEDULE'].includes(c.source)) throw new Invalid('INVALID_FIELD','source');
  number(c.target_portion_g,1,cfg.max_portion_g,'target_portion_g');
  number(c.created_at,1700000000,4102444800,'created_at',true);
  number(c.expires_at,1700000000,4102444800,'expires_at',true);
  if(c.expires_at<=c.created_at || c.expires_at-c.created_at>300 || c.created_at>now+10) throw new Invalid('INVALID_TIME');
  if(typeof c.override!=='boolean') throw new Invalid('INVALID_FIELD','override');
  if(c.override) throw new Invalid('OVERRIDE_NOT_SUPPORTED');
  if(checkExpiry && now>=c.expires_at) throw new Invalid('COMMAND_EXPIRED');
  return c;
}
export function schedules(items,cfg) {
  if(!Array.isArray(items)||items.length>8) throw new Invalid('INVALID_SCHEDULES');
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
export function sameCommand(a,b) { return ['command_id','source','target_portion_g','created_at','expires_at','override'].every(k=>a[k]===b[k]); }
