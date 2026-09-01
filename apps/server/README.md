# Enzo local app

The local API uses native Postgres as its source of truth. After a mutation, its
`legacy-sync.ts` adapter invokes the legacy CLI to upsert/delete the matching
Sheet event by ID and, for feed changes, reassert the shared Reminder using the
Postgres-calculated next-feed deadline. The adapter retries three times by
default; override that with `ENZO_LEGACY_SYNC_ATTEMPTS`.

Postgres success and legacy-sync success are reported separately. The iOS app
keeps the saved Postgres state and surfaces a visible warning if the Sheet or
Reminder could not be synchronized.

## First-time setup on macOS

```bash
brew install postgresql@17
brew services start postgresql@17
/opt/homebrew/opt/postgresql@17/bin/createdb enzo
```

Postgres initializes the schema automatically when the API starts:

```bash
cd apps/server
bun start
```

Open <http://127.0.0.1:4318>. The default connection is
`postgresql://localhost/enzo`; override it with `DATABASE_URL`.

## One-time legacy import

Download the Tracker tab as CSV, then import it without modifying the Sheet:

```bash
bun apps/server/import-tracker.ts '/path/to/Enzo Tracker - Tracker.csv'
```

The importer is idempotent. Rows with legacy event IDs retain them; paper
backfill rows receive deterministic IDs. It also corrects the legacy Sheet’s
mixed UTC/local-time behavior.

## Tailscale preview

The API listens on localhost. Expose it privately without opening a LAN port:

```bash
tailscale serve --bg --https=8443 localhost:4318
```

Do not reset other Serve routes on the Mac. Remove only this route with:

```bash
tailscale serve --https=8443 off
```

## Current trust model

- Postgres and the API bind locally on the Mac.
- Tailscale is the remote-access boundary.
- Deletes are soft deletes in Postgres.
- There are no user accounts yet; tailnet membership is the authorization layer.
