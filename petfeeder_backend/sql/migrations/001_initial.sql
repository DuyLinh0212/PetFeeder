BEGIN;

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS sync;

CREATE TABLE IF NOT EXISTS sync.schema_migrations (
  version         integer PRIMARY KEY,
  name            text NOT NULL,
  applied_at      timestamptz NOT NULL DEFAULT now()
);

-- Compatibility rows keep the existing feeding policy/service contract while
-- core tables below provide relational records for reports and other clients.
CREATE TABLE IF NOT EXISTS sync.records (
  bucket          text NOT NULL,
  id              text NOT NULL,
  ordinal         bigserial NOT NULL,
  body            jsonb NOT NULL,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (bucket, id)
);
CREATE INDEX IF NOT EXISTS ix_sync_records_bucket_order
  ON sync.records (bucket, ordinal DESC);

CREATE TABLE IF NOT EXISTS core.devices (
  device_id       text PRIMARY KEY,
  name            text NOT NULL DEFAULT 'Máy cho thú cưng ăn',
  timezone        text NOT NULL DEFAULT 'Asia/Bangkok',
  firmware_version text,
  last_seen_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS core.device_state (
  device_id       text PRIMARY KEY REFERENCES core.devices(device_id) ON DELETE CASCADE,
  status          text,
  busy            boolean NOT NULL DEFAULT false,
  food_level_percent smallint CHECK (food_level_percent BETWEEN 0 AND 100),
  bowl_weight_g   numeric(8,2),
  distance_cm     numeric(8,2),
  ip_address      text NOT NULL DEFAULT '',
  wifi_rssi       integer NOT NULL DEFAULT 0,
  locked          boolean NOT NULL DEFAULT false,
  time_valid      boolean NOT NULL DEFAULT false,
  sensor_mode     text NOT NULL DEFAULT 'UNKNOWN',
  boot_id         text,
  config_version  text,
  received_at     timestamptz NOT NULL,
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS core.device_settings (
  device_id       text PRIMARY KEY REFERENCES core.devices(device_id) ON DELETE CASCADE,
  settings        jsonb NOT NULL DEFAULT '{}'::jsonb,
  lan_api_base_url text,
  timezone        text NOT NULL DEFAULT 'Asia/Bangkok',
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS core.feeding_schedules (
  device_id       text NOT NULL REFERENCES core.devices(device_id) ON DELETE CASCADE,
  schedule_id     text NOT NULL,
  name            text NOT NULL,
  hour            smallint NOT NULL CHECK (hour BETWEEN 0 AND 23),
  minute          smallint NOT NULL CHECK (minute BETWEEN 0 AND 59),
  target_portion_g numeric(8,2) NOT NULL CHECK (target_portion_g > 0),
  days            smallint[] NOT NULL CHECK (cardinality(days) BETWEEN 1 AND 7),
  enabled         boolean NOT NULL,
  timezone        text NOT NULL DEFAULT 'Asia/Bangkok',
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (device_id, schedule_id)
);
CREATE INDEX IF NOT EXISTS ix_feeding_schedules_enabled_time
  ON core.feeding_schedules (device_id, enabled, hour, minute);

CREATE TABLE IF NOT EXISTS core.feeding_commands (
  device_id       text NOT NULL REFERENCES core.devices(device_id) ON DELETE CASCADE,
  command_id      text NOT NULL,
  source          text NOT NULL DEFAULT 'APP',
  status          text NOT NULL,
  target_portion_g numeric(8,2),
  actual_weight_g numeric(8,2),
  error_code      text,
  created_at      timestamptz,
  expires_at      timestamptz,
  occurred_at     timestamptz,
  last_seq        bigint NOT NULL DEFAULT 0,
  payload         jsonb NOT NULL,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (device_id, command_id)
);
CREATE INDEX IF NOT EXISTS ix_feeding_commands_recent
  ON core.feeding_commands (device_id, occurred_at DESC NULLS LAST);

CREATE TABLE IF NOT EXISTS core.feeding_history (
  device_id       text NOT NULL REFERENCES core.devices(device_id) ON DELETE CASCADE,
  command_id      text NOT NULL,
  event_id        text,
  source          text NOT NULL DEFAULT 'APP',
  status          text NOT NULL DEFAULT 'UNKNOWN',
  target_portion_g numeric(8,2),
  actual_weight_g numeric(8,2),
  error_code      text,
  occurred_at     timestamptz,
  scheduled_for   timestamptz,
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (device_id, command_id)
);
CREATE INDEX IF NOT EXISTS ix_feeding_history_recent
  ON core.feeding_history (device_id, occurred_at DESC NULLS LAST);

CREATE TABLE IF NOT EXISTS sync.device_events (
  device_id       text NOT NULL REFERENCES core.devices(device_id) ON DELETE CASCADE,
  boot_id         text NOT NULL,
  event_id        text NOT NULL,
  seq             bigint NOT NULL CHECK (seq > 0),
  event_type      text NOT NULL,
  occurred_at     timestamptz NOT NULL,
  received_at     timestamptz NOT NULL DEFAULT now(),
  payload         jsonb NOT NULL,
  PRIMARY KEY (device_id, event_id),
  CONSTRAINT device_events_device_boot_seq_key UNIQUE (device_id, boot_id, seq)
);
CREATE INDEX IF NOT EXISTS ix_device_events_recent
  ON sync.device_events (device_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS sync.command_outbox (
  device_id       text NOT NULL REFERENCES core.devices(device_id) ON DELETE CASCADE,
  command_id      text NOT NULL,
  state           text NOT NULL DEFAULT 'PENDING',
  payload         jsonb NOT NULL,
  queued_at       timestamptz NOT NULL DEFAULT now(),
  published_at    timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (device_id, command_id)
);
CREATE INDEX IF NOT EXISTS ix_command_outbox_pending
  ON sync.command_outbox (device_id, queued_at) WHERE state = 'PENDING';

INSERT INTO core.devices (device_id) VALUES ('petfeeder_01')
  ON CONFLICT (device_id) DO NOTHING;
INSERT INTO sync.schema_migrations (version, name)
  VALUES (1, 'initial_petfeeder_schema')
  ON CONFLICT (version) DO NOTHING;

COMMIT;
