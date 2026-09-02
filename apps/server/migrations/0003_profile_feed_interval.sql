-- The family-controlled feed interval is shared across devices. Existing
-- profiles move from the prior three-hour environment default to two hours.
ALTER TABLE profile
ADD COLUMN feed_interval_minutes INTEGER NOT NULL DEFAULT 120
CHECK (feed_interval_minutes >= 30 AND feed_interval_minutes <= 720);
