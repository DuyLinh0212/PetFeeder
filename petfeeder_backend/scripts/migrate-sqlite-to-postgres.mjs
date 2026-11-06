import {existsSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DatabaseSync} from 'node:sqlite';
import {PostgresStorage} from '../src/storage/postgres.mjs';

const backendDir=fileURLToPath(new URL('../',import.meta.url));
const source=resolve(process.env.SQLITE_PATH||`${backendDir}/data/main/backend.sqlite`);
if(!process.env.DATABASE_URL)throw new Error('Set DATABASE_URL to the Neon petfeeder database before importing.');
if(!existsSync(source))throw new Error(`SQLite source file was not found: ${source}`);

const sqlite=new DatabaseSync(source,{readOnly:true});
const postgres=new PostgresStorage(process.env.DATABASE_URL);
try {
  await postgres.initialize();
  const rows=sqlite.prepare('SELECT bucket,id,body FROM docs ORDER BY rowid ASC').all()
    .map(row=>({...row,body:JSON.parse(row.body)}));
  const inserted=await postgres.importRows(rows);
  const counts=new Map();
  for(const row of inserted)counts.set(row.bucket,(counts.get(row.bucket)||0)+1);
  console.log(`Imported ${[...counts.values()].reduce((sum,count)=>sum+count,0)} existing records into Neon.`);
  for(const [bucket,count] of counts)console.log(`  ${bucket}: ${count}`);
  console.log('Re-running this import is safe; existing bucket/id records are left unchanged.');
} finally {
  sqlite.close();
  await postgres.close();
}
