CREATE TABLE IF NOT EXISTS widget_push_tokens (
  token TEXT PRIMARY KEY,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  disabled_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_widget_push_tokens_active
ON widget_push_tokens(environment)
WHERE disabled_at IS NULL;
