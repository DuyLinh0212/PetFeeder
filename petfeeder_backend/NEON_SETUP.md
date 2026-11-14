# Neon PostgreSQL setup

1. In DBeaver, connect to the Neon database named in `PetFeeder/Key.txt` using a role with `CREATEDB` permission.
2. Open and run `sql/create_petfeeder_database.sql` once.
3. Change the DBeaver connection's database to `petfeeder`, then run `sql/migrations/001_initial.sql` and `sql/migrations/002_event_boot_sequence.sql` in order. The backend also applies both idempotent migrations at startup.
4. For local startup, `scripts/start_backend.ps1` reads the Neon URL from `PetFeeder/Key.txt` without printing it and changes only its database path to `/petfeeder`. Alternatively, set `DATABASE_URL` yourself.
5. For deployment, set `DATABASE_URL` in the host's secret environment settings. Never commit `Key.txt` or paste its URL into source files.

## Optional import of a legacy SQLite backup

The backend does not use SQLite at runtime. If you have an older SQLite backup that you still need to import, point `SQLITE_PATH` at that file; the utility inserts bucket records that do not already exist in Neon:

```powershell
$env:DATABASE_URL = '<Neon connection URL targeting database petfeeder>'
npm run migrate:sqlite
Remove-Item Env:DATABASE_URL
```

Set `SQLITE_PATH` to the backup's path before running the command. The importer reports counts only, not record contents. A local `data/main/backend.sqlite`, if present, is not needed for normal backend operation.
