# Enzo repository

This repository contains two independent modules:

- `apps/` is the current Postgres-backed iOS product.
- `legacy/sheets-reminders/` is the earlier Google Sheets and Apple Reminders tracker.

Route work by the system the user names. iOS, AlarmKit, Live Activity, dashboard,
Postgres, local API, and Tailscale requests belong to `apps/`. Google Sheet,
shared Home reminder, Apps Script, or `bin/enzo` requests belong to
`legacy/sheets-reminders/`. Each module has scoped `AGENTS.md` instructions.

Postgres is authoritative for the current app. App mutations mirror to the
legacy Sheet and shared Reminder only through `apps/server/legacy-sync.ts` and
the legacy CLI's private `sync-event` command.
