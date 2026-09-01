# Enzo

Enzo contains two generations of a baby-care tracker. They share a history and
a domain, but they are intentionally independent systems.

## Current app

[`apps/`](apps/) contains the Postgres-backed product:

- [`apps/server`](apps/server/) — a local Bun server and Postgres store, exposed
  privately over Tailscale.
- [`apps/ios`](apps/ios/) — the native SwiftUI app, Live Activity, and AlarmKit
  next-feed alarm.

Start with the [server setup](apps/server/README.md) and the
[iOS development guide](apps/ios/README.md).

## Legacy tracker

[`legacy/sheets-reminders`](legacy/sheets-reminders/) contains the original
agent-operated workflow: Google Sheets through Apps Script plus a shared urgent
Apple Reminder. Its history and setup live in the
[legacy README](legacy/sheets-reminders/README.md).

Postgres remains authoritative for the current app. After each app mutation,
the server uses one explicit CLI adapter to mirror the event into the legacy
Sheet and move the shared Reminder to the Postgres-calculated next-feed time.
The legacy CSV importer remains a one-time migration tool.
