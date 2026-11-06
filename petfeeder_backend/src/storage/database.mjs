import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
export class Storage {
  constructor(file=':memory:') {
    if(file!==':memory:') mkdirSync(dirname(file),{recursive:true});
    this.db=new DatabaseSync(file);
    this.db.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS docs (bucket TEXT NOT NULL, id TEXT NOT NULL, body TEXT NOT NULL, PRIMARY KEY(bucket,id));');
  }
  get(bucket,id='state') { const row=this.db.prepare('SELECT body FROM docs WHERE bucket=? AND id=?').get(bucket,id); return row ? JSON.parse(row.body):null; }
  put(bucket,id,body) { this.db.prepare('INSERT INTO docs VALUES(?,?,?) ON CONFLICT(bucket,id) DO UPDATE SET body=excluded.body').run(bucket,id,JSON.stringify(body)); return body; }
  putIfAbsent(bucket,id,body) {
    const result=this.db.prepare('INSERT OR IGNORE INTO docs VALUES(?,?,?)').run(bucket,id,JSON.stringify(body));
    return result.changes===1;
  }
  all(bucket) { return this.db.prepare('SELECT body FROM docs WHERE bucket=? ORDER BY rowid DESC').all(bucket).map(r=>JSON.parse(r.body)); }
  transaction(fn) {
    this.db.exec('BEGIN IMMEDIATE');
    const commit=value=>{this.db.exec('COMMIT');return value;};
    const rollback=error=>{try{this.db.exec('ROLLBACK');}catch{}throw error;};
    try {
      const result=fn();
      return result&&typeof result.then==='function'?result.then(commit,rollback):commit(result);
    } catch(error) { return rollback(error); }
  }
  close(){this.db.close();}
}
