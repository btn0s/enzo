# Legacy Sheets and Reminders tracker

For every feeding, pee, poop, combined diaper, or tracker-status request scoped
to this legacy tracker, read [AUTOMATION.md](AUTOMATION.md) and use `bin/enzo`.
The CLI is the single write path for its Google Sheet and `Feed Enzo` reminder.

The current app calls the private `sync-event` command with a JSON mutation
envelope on stdin. Keep its Apps Script upsert/delete operations idempotent by
event ID so server retries cannot duplicate Sheet rows.
