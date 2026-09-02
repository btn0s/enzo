-- Profile: a single row (id = 1) with facts about Enzo that every device shares.
CREATE TABLE IF NOT EXISTS profile (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  birth_at TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

INSERT OR IGNORE INTO profile (id, birth_at) VALUES (1, '2026-08-29T04:00:00.000Z');

-- Checkups: clinician visits. The latest checkup on or before "now" is the
-- active care plan. Every goal column is nullable; NULL means "use the
-- published guidance for Enzo's age and weight".
CREATE TABLE IF NOT EXISTS checkups (
  id TEXT PRIMARY KEY,
  occurred_at TEXT NOT NULL,
  weight_kg REAL CHECK (weight_kg IS NULL OR (weight_kg > 0 AND weight_kg <= 30)),
  feed_interval_minutes INTEGER CHECK (feed_interval_minutes IS NULL OR (feed_interval_minutes >= 30 AND feed_interval_minutes <= 720)),
  feeds_min INTEGER CHECK (feeds_min IS NULL OR (feeds_min >= 1 AND feeds_min <= 24)),
  feeds_max INTEGER CHECK (feeds_max IS NULL OR (feeds_max >= 1 AND feeds_max <= 24)),
  bottle_ml REAL CHECK (bottle_ml IS NULL OR (bottle_ml > 0 AND bottle_ml <= 500)),
  milk_ml_min REAL CHECK (milk_ml_min IS NULL OR (milk_ml_min > 0 AND milk_ml_min <= 3000)),
  milk_ml_max REAL CHECK (milk_ml_max IS NULL OR (milk_ml_max > 0 AND milk_ml_max <= 3000)),
  pee_min INTEGER CHECK (pee_min IS NULL OR (pee_min >= 0 AND pee_min <= 30)),
  poop_min INTEGER CHECK (poop_min IS NULL OR (poop_min >= 0 AND poop_min <= 30)),
  notes TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  CHECK (feeds_min IS NULL OR feeds_max IS NULL OR feeds_min <= feeds_max),
  CHECK (milk_ml_min IS NULL OR milk_ml_max IS NULL OR milk_ml_min <= milk_ml_max)
);

CREATE INDEX IF NOT EXISTS checkups_occurred_at_idx
  ON checkups (occurred_at DESC) WHERE deleted_at IS NULL;
