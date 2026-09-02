# Enzo repository

This repository contains two independent modules:

- `apps/` is the current Cloudflare-backed iOS product.
- `legacy/sheets-reminders/` is the earlier Google Sheets and Apple Reminders tracker.

Route work by the system the user names. iOS, AlarmKit, Live Activity, dashboard,
Worker, D1, and Cloudflare requests belong to `apps/`. Google Sheet,
shared Home reminder, Apps Script, or `bin/enzo` requests belong to
`legacy/sheets-reminders/`. Each module has scoped `AGENTS.md` instructions.

D1, behind the `apps/server` Worker, is authoritative for the current app. The
legacy tracker stands alone; nothing in `apps/` calls into it.
