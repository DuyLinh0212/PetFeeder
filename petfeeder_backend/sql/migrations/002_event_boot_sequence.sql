BEGIN;

ALTER TABLE sync.device_events
  ADD COLUMN IF NOT EXISTS boot_id text NOT NULL DEFAULT 'legacy';
ALTER TABLE sync.device_events
  DROP CONSTRAINT IF EXISTS device_events_device_id_seq_key;
ALTER TABLE sync.device_events
  DROP CONSTRAINT IF EXISTS device_events_device_boot_seq_key;
ALTER TABLE sync.device_events
  ADD CONSTRAINT device_events_device_boot_seq_key UNIQUE (device_id,boot_id,seq);

INSERT INTO sync.schema_migrations (version,name)
  VALUES (2,'event_sequence_scoped_to_boot')
  ON CONFLICT (version) DO NOTHING;

COMMIT;
