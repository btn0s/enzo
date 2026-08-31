# Enzo tracking automation

Use `bin/enzo` for every tracker change. It writes through the Apps Script endpoint and moves the shared reminder as one workflow.

## Commands

```bash
bin/enzo feed --milk formula --amount 12 --at "2026-01-15 20:43" --notes "Small feed; may feed sooner."
bin/enzo feed --milk breast-milk --amount 30
bin/enzo update-feed --amount 12 --notes "Small feed; may feed sooner."
bin/enzo pee
bin/enzo poop
bin/enzo both
bin/enzo status
```

Times without an offset use `America/Phoenix`. A feeding moves the single incomplete `Feed Enzo` reminder in the shared `Home` list to three hours after the feeding and turns on Urgent. Diaper events never move it. If the amount is not known yet, omit `--amount`, then use `update-feed` when the bottle is finished. `update-feed` edits the most recent feeding row and reasserts its reminder without creating a second feed.

When a feed reports that the sheet write succeeded but the reminder failed, run the printed `repair-reminder` command. The event ID makes sheet retries safe from duplicate rows.

Configuration comes from exported `ENZO_*` variables or the ignored `.env` file. Run `bin/enzo configure --endpoint URL`; the token is requested without echo and `.env` is written with user-only permissions. Environment variables override `.env`.

Do not edit the Sheet and reminder separately for a normal tracking request. Report the event time, amount/milk when applicable, and next-feed time from the CLI output.
