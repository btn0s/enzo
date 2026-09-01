# Enzo tracking automation

Use `bin/enzo` for every tracker change. It writes through the Apps Script endpoint and moves the shared reminder as one workflow.

## Commands

```bash
bin/enzo feed --milk formula --amount 12 --at "2026-01-15 20:43" --notes "Small feed; may feed sooner."
bin/enzo feed --milk breast-milk --amount 30
bin/enzo update-feed --amount 12 --notes "Small feed; may feed sooner."
bin/enzo diaper --pee
bin/enzo diaper --poop
bin/enzo diaper --pee --poop
bin/enzo status
```

Times without an offset use `America/Phoenix`. A feed moves the single incomplete `Feed Enzo` reminder in the shared `Home` list to three hours after the feed and turns on Urgent. A diaper contains `pee`, `poop`, or both and never moves the reminder. If the amount is not known yet, omit `--amount`, then use `update-feed` when the bottle is finished. `update-feed` edits the most recent feed row and reasserts its reminder without creating a second feed.

The reminder operation is idempotent and retries up to `ENZO_REMINDER_ATTEMPTS` times (three by default). Each attempt must move the one incomplete reminder, turn on Urgent, and verify the saved due time and Urgent state. Only after the retry limit is exhausted does the command report that the sheet write succeeded and print a `repair-reminder` command. The event ID makes sheet retries safe from duplicate rows.

Configuration comes from exported `ENZO_*` variables or the ignored `.env` file. Run `bin/enzo configure --endpoint URL`; the token is requested without echo and `.env` is written with user-only permissions. Environment variables override `.env`.

Do not edit the Sheet and reminder separately for a normal tracking request. Report the event time, amount/milk when applicable, and next-feed time from the CLI output.

`sync-event` is reserved for the current app server. It reads a JSON mutation
envelope from stdin, performs an idempotent Sheet upsert/delete by event ID, and
sets the Reminder to the exact `nextFeedAt` supplied by Postgres.
