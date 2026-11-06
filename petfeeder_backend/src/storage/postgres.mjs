import {readFile} from 'node:fs/promises';
import {AsyncLocalStorage} from 'node:async_hooks';
import {fileURLToPath} from 'node:url';
import {Pool} from 'pg';

const DEFAULT_DEVICE_ID='petfeeder_01';
const TERMINAL_STATUSES=new Set([
  'SUCCESS','PARTIAL','INTERRUPTED','REJECTED','COMMAND_EXPIRED',
  'SENSOR_ERROR','BOWL_MISSING','TIMEOUT','OVER_PORTION','DELIVERY_FAILED',
]);
const epochDate=value=>Number.isFinite(Number(value))?new Date(Number(value)*1000):null;

function normalizeSslMode(connectionString){
  const url=new URL(connectionString);
  if(url.searchParams.get('sslmode')?.toLowerCase()==='require')url.searchParams.set('sslmode','verify-full');
  return url.toString();
}

export class PostgresStorage {
  constructor(connectionString,{poolOptions={}}={}) {
    if(!connectionString)throw new Error('DATABASE_URL_REQUIRED');
    this.pool=new Pool({
      connectionString:normalizeSslMode(connectionString),
      max:8,
      idleTimeoutMillis:30000,
      connectionTimeoutMillis:10000,
      ...poolOptions,
    });
    this.transactionContext=new AsyncLocalStorage();
  }

  get activeClient(){return this.transactionContext.getStore()||null;}

  async initialize() {
    await this.pool.query('SELECT 1');
    const client=await this.pool.connect();
    try {
      for(const file of ['001_initial.sql','002_event_boot_sequence.sql']){
        const sql=await readFile(fileURLToPath(new URL(`../../sql/migrations/${file}`,import.meta.url)),'utf8');
        await client.query(sql);
      }
    }
    finally { client.release(); }
    await this.pool.query(
      `INSERT INTO core.devices (device_id) VALUES ($1) ON CONFLICT (device_id) DO NOTHING`,
      [DEFAULT_DEVICE_ID],
    );
  }

  async _withClient(work) {
    if(this.activeClient)return work(this.activeClient);
    const client=await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result=await this.transactionContext.run(client,()=>work(client));
      await client.query('COMMIT');
      return result;
    } catch(error) {
      try { await client.query('ROLLBACK'); } catch {}
      throw error;
    } finally {
      client.release();
    }
  }

  async transaction(work) {
    if(this.activeClient)return work();
    return this._withClient(()=>work());
  }

  async get(bucket,id='state') {
    const result=await (this.activeClient||this.pool).query(
      'SELECT body FROM sync.records WHERE bucket=$1 AND id=$2',[bucket,id],
    );
    return result.rowCount?result.rows[0].body:null;
  }

  async all(bucket) {
    const limit=bucket==='events'?' LIMIT 200':'';
    const result=await (this.activeClient||this.pool).query(
      `SELECT body FROM sync.records WHERE bucket=$1 ORDER BY ordinal DESC${limit}`,[bucket],
    );
    return result.rows.map(row=>row.body);
  }

  async put(bucket,id,body) {
    return this._withClient(async client=>{
      await client.query(
        `INSERT INTO sync.records (bucket,id,body) VALUES ($1,$2,$3::jsonb)
         ON CONFLICT (bucket,id) DO UPDATE SET body=EXCLUDED.body,updated_at=now()`,
        [bucket,id,JSON.stringify(body)],
      );
      await this._project(client,bucket,id,body);
      return body;
    });
  }

  async putIfAbsent(bucket,id,body) {
    return this._withClient(async client=>{
      const inserted=await client.query(
        `INSERT INTO sync.records (bucket,id,body) VALUES ($1,$2,$3::jsonb)
         ON CONFLICT (bucket,id) DO NOTHING RETURNING id`,
        [bucket,id,JSON.stringify(body)],
      );
      if(!inserted.rowCount)return false;
      await this._project(client,bucket,id,body);
      return true;
    });
  }

  async importRows(rows) {
    if(!rows.length)return [];
    return this.transaction(async()=>{
      const inserted=await this.activeClient.query(
        `INSERT INTO sync.records (bucket,id,body)
         SELECT batch.bucket,batch.id,batch.body::jsonb
         FROM unnest($1::text[],$2::text[],$3::text[]) AS batch(bucket,id,body)
         ON CONFLICT (bucket,id) DO NOTHING RETURNING bucket,id`,
        [rows.map(row=>row.bucket),rows.map(row=>row.id),rows.map(row=>JSON.stringify(row.body))],
      );
      const newKeys=new Set(inserted.rows.map(row=>`${row.bucket}\u001f${row.id}`));
      const newRows=rows.filter(row=>newKeys.has(`${row.bucket}\u001f${row.id}`));
      const eventRows=newRows.filter(row=>row.bucket==='events');
      for(const row of newRows)if(row.bucket!=='events')await this._project(this.activeClient,row.bucket,row.id,row.body);
      if(eventRows.length){
        const eventJson=JSON.stringify(eventRows.map(row=>row.body));
        await this.activeClient.query(
          `WITH incoming AS (
             SELECT value AS body FROM jsonb_array_elements($1::jsonb)
           ), device_ids AS (
             SELECT DISTINCT COALESCE(NULLIF(body->>'device_id',''),'petfeeder_01') AS device_id FROM incoming
           )
           INSERT INTO core.devices (device_id)
           SELECT device_id FROM device_ids ON CONFLICT (device_id) DO NOTHING`,[eventJson],
        );
        await this.activeClient.query(
          `INSERT INTO sync.device_events (device_id,boot_id,event_id,seq,event_type,occurred_at,payload)
           SELECT COALESCE(NULLIF(body->>'device_id',''),'petfeeder_01'),
                  COALESCE(NULLIF(body->>'boot_id',''),'legacy:'||(body->>'event_id')),
                  body->>'event_id',(body->>'seq')::bigint,
                  COALESCE(body->>'status',body->>'event','UNKNOWN'),
                  to_timestamp(COALESCE(NULLIF(body->>'occurred_at','')::double precision,extract(epoch from now()))),
                  body
           FROM jsonb_array_elements($1::jsonb) AS item(body)`,[eventJson],
        );
      }
      return newRows;
    });
  }

  async _ensureDevice(client,deviceId=DEFAULT_DEVICE_ID) {
    await client.query(
      `INSERT INTO core.devices (device_id) VALUES ($1)
       ON CONFLICT (device_id) DO UPDATE SET updated_at=now()`,[deviceId],
    );
  }

  async _project(client,bucket,id,body) {
    const deviceId=body?.device_id||DEFAULT_DEVICE_ID;
    if(['config','schedules','heartbeat','commands','legacy_history','events','connection'].includes(bucket)) {
      await this._ensureDevice(client,deviceId);
    }

    if(bucket==='config') {
      await client.query(
        `INSERT INTO core.device_settings (device_id,settings,timezone)
         VALUES ($1,$2::jsonb,'Asia/Bangkok')
         ON CONFLICT (device_id) DO UPDATE SET settings=EXCLUDED.settings,updated_at=now()`,
        [deviceId,JSON.stringify(body||{})],
      );
    } else if(bucket==='connection') {
      await client.query(
        `INSERT INTO core.device_settings (device_id,settings,lan_api_base_url,timezone)
         VALUES ($1,'{}'::jsonb,$2,'Asia/Bangkok')
         ON CONFLICT (device_id) DO UPDATE SET lan_api_base_url=EXCLUDED.lan_api_base_url,updated_at=now()`,
        [deviceId,body?.connection_address||null],
      );
    } else if(bucket==='schedules') {
      await client.query('DELETE FROM core.feeding_schedules WHERE device_id=$1',[deviceId]);
      for(const schedule of Array.isArray(body)?body:[]) {
        await client.query(
          `INSERT INTO core.feeding_schedules
            (device_id,schedule_id,name,hour,minute,target_portion_g,days,enabled,timezone,payload)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'Asia/Bangkok',$9::jsonb)`,
          [deviceId,schedule.schedule_id,schedule.name||'Lịch cho ăn',schedule.hour,schedule.minute,
            schedule.target_portion_g,schedule.days,schedule.enabled,JSON.stringify(schedule)],
        );
      }
    } else if(bucket==='heartbeat') {
      const receivedAt=epochDate(body?.received_at)||new Date();
      await client.query(
        `UPDATE core.devices SET last_seen_at=$2,updated_at=now() WHERE device_id=$1`,[deviceId,receivedAt],
      );
      await client.query(
        `INSERT INTO core.device_state
          (device_id,status,busy,food_level_percent,bowl_weight_g,distance_cm,ip_address,wifi_rssi,
           locked,time_valid,sensor_mode,boot_id,config_version,received_at,payload)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15::jsonb)
         ON CONFLICT (device_id) DO UPDATE SET
           status=EXCLUDED.status,busy=EXCLUDED.busy,food_level_percent=EXCLUDED.food_level_percent,
           bowl_weight_g=EXCLUDED.bowl_weight_g,distance_cm=EXCLUDED.distance_cm,
           ip_address=EXCLUDED.ip_address,wifi_rssi=EXCLUDED.wifi_rssi,locked=EXCLUDED.locked,
           time_valid=EXCLUDED.time_valid,sensor_mode=EXCLUDED.sensor_mode,boot_id=EXCLUDED.boot_id,
           config_version=EXCLUDED.config_version,received_at=EXCLUDED.received_at,payload=EXCLUDED.payload`,
        [deviceId,body?.status||null,body?.busy===true,body?.food_level_percent??null,body?.weight_g??null,
          body?.distance_cm??null,body?.ip||'',body?.rssi||0,body?.locked===true,body?.time_valid===true,
          body?.sensor_mode||'UNKNOWN',body?.boot_id||null,body?.config_version||null,receivedAt,JSON.stringify(body||{})],
      );
    } else if(bucket==='commands') {
      const createdAt=epochDate(body?.created_at),expiresAt=epochDate(body?.expires_at);
      const occurredAt=epochDate(body?.occurred_at??body?.updated_at??body?.created_at);
      await client.query(
        `INSERT INTO core.feeding_commands
          (device_id,command_id,source,status,target_portion_g,actual_weight_g,error_code,created_at,
           expires_at,occurred_at,last_seq,payload,updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::jsonb,now())
         ON CONFLICT (device_id,command_id) DO UPDATE SET
           source=EXCLUDED.source,status=EXCLUDED.status,target_portion_g=EXCLUDED.target_portion_g,
           actual_weight_g=EXCLUDED.actual_weight_g,error_code=EXCLUDED.error_code,
           created_at=COALESCE(core.feeding_commands.created_at,EXCLUDED.created_at),
           expires_at=COALESCE(core.feeding_commands.expires_at,EXCLUDED.expires_at),
           occurred_at=EXCLUDED.occurred_at,last_seq=GREATEST(core.feeding_commands.last_seq,EXCLUDED.last_seq),
           payload=EXCLUDED.payload,updated_at=now()`,
        [deviceId,body.command_id,body.source||'APP',body.status||'UNKNOWN',body.target_portion_g??null,
          body.actual_weight_g??null,body.error_code||null,createdAt,expiresAt,occurredAt,body.last_seq||body.seq||0,JSON.stringify(body)],
      );
      await client.query(
        `INSERT INTO core.feeding_history
          (device_id,command_id,source,status,target_portion_g,actual_weight_g,error_code,occurred_at,payload)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb)
         ON CONFLICT (device_id,command_id) DO UPDATE SET
           source=EXCLUDED.source,status=EXCLUDED.status,target_portion_g=EXCLUDED.target_portion_g,
           actual_weight_g=EXCLUDED.actual_weight_g,error_code=EXCLUDED.error_code,
           occurred_at=EXCLUDED.occurred_at,payload=EXCLUDED.payload`,
        [deviceId,body.command_id,body.source||'APP',body.status||'UNKNOWN',body.target_portion_g??null,
          body.actual_weight_g??null,body.error_code||null,occurredAt,JSON.stringify(body)],
      );
      if(body.status==='QUEUED') {
        await client.query(
          `INSERT INTO sync.command_outbox (device_id,command_id,state,payload)
           VALUES ($1,$2,'PENDING',$3::jsonb)
           ON CONFLICT (device_id,command_id) DO UPDATE SET
             state=CASE WHEN sync.command_outbox.state='PENDING' THEN 'PENDING' ELSE sync.command_outbox.state END,
             payload=EXCLUDED.payload,updated_at=now()`,
          [deviceId,body.command_id,JSON.stringify(body)],
        );
      } else {
        const state=body.status==='DELIVERY_FAILED'?'FAILED':TERMINAL_STATUSES.has(body.status)?'COMPLETED':'PUBLISHED';
        await client.query(
          `UPDATE sync.command_outbox SET state=$3,updated_at=now()
           WHERE device_id=$1 AND command_id=$2`,[deviceId,body.command_id,state],
        );
      }
    } else if(bucket==='legacy_history') {
      const commandId=body?.command_id||body?.id||`legacy-${id}`;
      const happenedAt=Number.isFinite(Number(body?.occurred_at))?epochDate(body.occurred_at):
        Number.isFinite(Date.parse(body?.timestamp||''))?new Date(body.timestamp):null;
      const actual=body?.actual_weight_g??body?.actual_g??null;
      await client.query(
        `INSERT INTO core.feeding_history
          (device_id,command_id,source,status,target_portion_g,actual_weight_g,error_code,occurred_at,payload)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb)
         ON CONFLICT (device_id,command_id) DO NOTHING`,
        [deviceId,commandId,body?.source||'APP',body?.status||(typeof actual==='number'?'SUCCESS':'UNKNOWN'),
          body?.target_portion_g??body?.portion_g??body?.portion??null,actual,body?.error_code||null,happenedAt,JSON.stringify(body)],
      );
    } else if(bucket==='events') {
      await client.query(
        `INSERT INTO sync.device_events (device_id,boot_id,event_id,seq,event_type,occurred_at,payload)
         VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb)`,
        [deviceId,body.boot_id||`legacy:${body.event_id}`,body.event_id,body.seq,body.status||body.event||'UNKNOWN',
          epochDate(body.occurred_at)||new Date(),JSON.stringify(body)],
      );
    }
  }

  async history(limit=50) {
    const result=await this.pool.query(
      `SELECT command_id,source,target_portion_g,actual_weight_g,status,error_code,
              EXTRACT(EPOCH FROM occurred_at)::bigint AS occurred_at
       FROM core.feeding_history WHERE device_id=$1
       ORDER BY occurred_at DESC NULLS LAST LIMIT $2`,[DEFAULT_DEVICE_ID,limit],
    );
    return result.rows.map(row=>({...row,occurred_at:row.occurred_at===null?null:Number(row.occurred_at)}));
  }

  async markCommandPublished(commandId) {
    await this.pool.query(
      `UPDATE sync.command_outbox SET state='PUBLISHED',published_at=now(),updated_at=now()
       WHERE device_id=$1 AND command_id=$2 AND state='PENDING'`,[DEFAULT_DEVICE_ID,commandId],
    );
  }

  async pendingCommands() {
    const result=await this.pool.query(
      `SELECT body FROM sync.records WHERE bucket='commands' AND body->>'status'='QUEUED'
       ORDER BY ordinal ASC`,
    );
    return result.rows.map(row=>row.body);
  }

  async health() {
    await this.pool.query('SELECT 1');
    return true;
  }

  async close() { await this.pool.end(); }
}
