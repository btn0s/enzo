# Enzo tracker automation

A dependency-free local CLI plus a Google Apps Script web endpoint for Enzo's feeding and diaper tracker.

Canonical repository: [btn0s/enzo](https://github.com/btn0s/enzo)

The CLI is the single entry point. It posts an idempotent event to the Google Sheet and, after a feeding, moves one `Feed Enzo` item in the shared `Home` Reminders list to three hours later. The reminder is marked Urgent through the Reminders UI because Apple has not exposed the iOS 26.2 Urgent property through AppleScript or EventKit.

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
