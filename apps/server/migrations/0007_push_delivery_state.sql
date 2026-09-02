CREATE TABLE IF NOT EXISTS push_delivery_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  live_activity_timestamp INTEGER NOT NULL
);

INSERT OR IGNORE INTO push_delivery_state (id, live_activity_timestamp)
VALUES (1, unixepoch());
