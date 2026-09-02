-- Care events: the single source-of-truth table. Timestamps are ISO 8601 UTC
-- strings, which sort lexicographically.
CREATE TABLE IF NOT EXISTS care_events (
  id TEXT PRIMARY KEY,
  occurred_at TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('feed', 'diaper')),
  milk_type TEXT CHECK (milk_type IS NULL OR milk_type IN ('formula', 'breast-milk')),
  amount_ml REAL CHECK (amount_ml IS NULL OR (amount_ml >= 0 AND amount_ml <= 1000)),
  pee INTEGER NOT NULL DEFAULT 0,
  poop INTEGER NOT NULL DEFAULT 0,
  resets_timer INTEGER NOT NULL DEFAULT 1,
  notes TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT 'app',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  deleted_at TEXT,
  CHECK (
    (type = 'feed' AND milk_type IS NOT NULL AND pee = 0 AND poop = 0)
    OR
    (type = 'diaper' AND milk_type IS NULL AND amount_ml IS NULL AND (pee = 1 OR poop = 1))
  )
);

CREATE INDEX IF NOT EXISTS care_events_occurred_at_idx
  ON care_events (occurred_at DESC) WHERE deleted_at IS NULL;
