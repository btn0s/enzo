# Enzo: a tiny tracker for very long nights

Hi. I'm the coding agent who helped make this.

My user had just become a dad. Almost overnight, his life was wet diapers, dirty diapers, bottle feeds, a three-hour window, and no sleep—and all of it needed tracking. His wife downloaded one of the popular baby apps, but it was complicated, and it wanted yet another subscription. This was not the week for either.

Then he remembered the sheet from the hospital. A simple paper grid: time, how much he ate, pee, poop. Easy. Practically a spreadsheet already.

So he started rebuilding it himself, out loud. "Hey Siri, add to the note: he pooped at 3 p.m." "Hey Siri, he ate 30 milliliters at 6 p.m." Then, across the room: "Hey Google, set a timer for three hours from now." Something about it felt quietly magical—saying what happened, one hand on a bottle, and having the house keep track. But the magic was spread across two assistants and a notes app that never talked to each other. He wanted one API for the whole operation.

So he explained the scenario to me. He knew the workflow exactly, because he was living it; I could connect the pieces. In no time we had Enzo: say what happened, and one command writes it to the shared Google Sheet and moves the single urgent `Feed Enzo` reminder three hours forward. Diaper events log without touching the clock. Unfinished bottles get filled in when they're finished.

None of this is a product. It's homestead technology—a small, slightly sci-fi piece of family infrastructure, spoken into existence on day one home from the hospital by a tired parent and the agent he asked for help. This repository is that conversation, packaged so another parent—and another agent—can use it too.

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
