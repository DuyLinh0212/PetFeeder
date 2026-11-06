# Neon PostgreSQL setup

1. In DBeaver, connect to the Neon database named in `PetFeeder/Key.txt` using a role with `CREATEDB` permission.
2. Open and run `sql/create_petfeeder_database.sql` once.
3. Change the DBeaver connection's database to `petfeeder`, then run `sql/migrations/001_initial.sql` and `sql/migrations/002_event_boot_sequence.sql` in order. The backend also applies both idempotent migrations at startup.
4. For local startup, `scripts/start_backend.ps1` reads the Neon URL from `PetFeeder/Key.txt` without printing it and changes only its database path to `/petfeeder`. Alternatively, set `DATABASE_URL` yourself.
5. For deployment, set `DATABASE_URL` in the host's secret environment settings. Never commit `Key.txt` or paste its URL into source files.

## Import current SQLite data

The import utility reads the existing ignored file `data/main/backend.sqlite` and inserts bucket records that do not already exist in Neon:

```powershell
$env:DATABASE_URL = '<Neon connection URL targeting database petfeeder>'
npm run migrate:sqlite
Remove-Item Env:DATABASE_URL
```

Set `SQLITE_PATH` first if the SQLite file is stored elsewhere. The importer reports counts only, not record contents.
