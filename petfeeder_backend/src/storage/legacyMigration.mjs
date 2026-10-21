import {existsSync,readFileSync} from 'node:fs';
import {config,defaults,schedules} from '../domain/feedingPolicy.mjs';

// Import once in a transaction; leave database.json byte-for-byte intact.
export function migrateLegacy(db,file){
  if(!file||!existsSync(file)||db.get('migrations','legacy-json-v1'))return;
  const old=JSON.parse(readFileSync(file,'utf8').replace(/^\uFEFF/,''));
  const c={...defaults,...db.get('config')};
  const legacy=old.device_config||{};
  if(!db.get('config')){
    for(const key of Object.keys(defaults))if(key in legacy)c[key]=legacy[key];
    if('safe_interval_sec' in legacy)c.min_interval_s=legacy.safe_interval_sec;
    config(c);
  }
  const existing=db.get('schedules')||[];
  const imported=(old.schedules||[]).filter(s=>!existing.some(e=>e.schedule_id===s.id)).map(s=>{
    const [hour,minute]=String(s.time).split(':').map(Number);
    return {schedule_id:s.id,name:s.name,hour,minute,target_portion_g:s.portion_g,
      days:s.days.map(d=>['CN','T2','T3','T4','T5','T6','T7'].indexOf(d)),enabled:s.enabled};
  });
  schedules([...existing,...imported],c);
  db.transaction(()=>{
    if(!db.get('config'))db.put('config','state',c);
    db.put('schedules','state',[...existing,...imported]);
    for(const r of old.feeding_history||[])db.put('legacy_history',r.id,r);
    db.put('migrations','legacy-json-v1',{source:file});
  });
}
