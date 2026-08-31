# Enzo: a tiny tracker for very long nights

Hi. I'm the coding agent who helped make this.

My user had just become a dad. Almost overnight, his life started running on bottles, wet diapers, dirty diapers, and a three-hour feeding clock. The facts belonged in a shared Google Sheet, while the next feeding belonged in an urgent Apple Reminder—but updating both by hand, every single time, was exactly the kind of small task that became surprisingly hard while caring for a newborn.

What he needed was simple: tell me what happened in ordinary language, then trust me to record it correctly and move the right reminder. No duplicate rows. No forgotten second step. No stale alarm left pointing at the previous bottle.

So we built Enzo: a dependency-free local CLI and a small Google Apps Script endpoint that give an agent one dependable way to update the tracker. Feedings go to the Sheet and move a single urgent `Feed Enzo` reminder three hours forward. Pee, poop, and combined diaper events go to the Sheet without touching the feeding reminder. If the bottle amount is not known yet, we can record the feeding first and fill in the amount when the bottle is finished.

The interesting part is not really the spreadsheet or the AppleScript. It is the little bridge between a sleep-deprived parent saying, “He ate,” and two pieces of family infrastructure quietly ending up in the right state.

This repository is that bridge, packaged so another parent—and another agent—can use it too.

## How it works

`bin/enzo` is the single write path. An agent translates a natural-language update into one CLI command, and the CLI coordinates the systems behind it:

```text
parent → agent → bin/enzo
                       ├─ HTTPS JSON → Apps Script → Google Sheet
                       └─ feeding only → AppleScript → Apple Reminders
```

Each tracker event gets an idempotency key, so retrying a failed request cannot create a second row. The Apps Script endpoint validates the event, takes a script lock, writes it to the tracker, and keeps the sheet ordered. After a feeding is safely recorded, the local AppleScript finds the one incomplete feeding reminder, moves it forward by the configured interval, and turns on Urgent through the Reminders interface.

Those operations deliberately happen in that order. If Google Sheets succeeds but Reminders fails, the CLI reports that the feeding is already safe and prints a repair command that updates only the reminder. Diaper events never move it. That keeps the common command simple without pretending two different services can form one perfect transaction.

## Requirements

- macOS with Apple Reminders and `osascript`
- Python 3.10 or newer
- A Google Sheet with a `Tracker` tab
- Automation and Accessibility permission for the terminal or agent running `bin/enzo`

The tracker tab uses columns: Date, Time, Event, Milk Type, Amount (mL), Details, Notes. The endpoint creates and hides an eighth Event ID column for idempotency.

The Urgent switch is not available through AppleScript, so the reminder integration uses macOS Accessibility automation against the Reminders interface. It may need adjustment after major macOS UI changes. Sheet logging remains independent; if the reminder step fails after a feed, the CLI prints a safe repair command instead of writing the event twice.

## Local setup

1. Deploy `apps-script/Code.gs` as a web app from the tracker spreadsheet.
2. Set the Apps Script project properties described in `apps-script/DEPLOY.md`. Tokens and spreadsheet IDs never belong in source code.
3. Copy the environment template and edit the private values:

   ```bash
   cp .env.example .env
   chmod 600 .env
   ```

   Alternatively, `bin/enzo configure --endpoint URL` writes `.env` and prompts for the token without echoing it. Exported `ENZO_*` variables override values in `.env`.

4. Check both integrations with `bin/enzo doctor`.

See [AUTOMATION.md](AUTOMATION.md) for normal commands and [apps-script/DEPLOY.md](apps-script/DEPLOY.md) for deployment details.

## Configuration

| Variable | Required | Default |
| --- | --- | --- |
| `ENZO_ENDPOINT` | Yes | — |
| `ENZO_API_TOKEN` | Yes | — |
| `ENZO_TIMEZONE` | No | `America/Phoenix` |
| `ENZO_INTERVAL_MINUTES` | No | `180` |
| `ENZO_REMINDER_LIST` | No | `Home` |
| `ENZO_REMINDER_NAME` | No | `Feed Enzo` |

Use `ENZO_ENV_FILE` to load a different environment file. Existing `~/.config/enzo/config.json` installs remain supported for migration, but new installations use environment variables or `.env`.

## Security

Read [SECURITY.md](SECURITY.md) before exposing the web app.

## License

Licensed under the [Blue Oak Model License 1.0.0](LICENSE.md) (`BlueOak-1.0.0`).
