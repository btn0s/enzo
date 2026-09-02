CREATE TABLE IF NOT EXISTS live_activity_tokens (
  token TEXT PRIMARY KEY,
  activity_id TEXT NOT NULL,
  event_id TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  disabled_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_live_activity_tokens_active
ON live_activity_tokens(environment)
WHERE disabled_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_live_activity_tokens_activity
ON live_activity_tokens(activity_id)
WHERE disabled_at IS NULL;
