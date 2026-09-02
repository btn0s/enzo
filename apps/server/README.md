# Enzo API (Cloudflare Worker)

The API runs on Cloudflare Workers with D1 as the source of truth, deployed at
`https://enzo-api.btn0s.workers.dev`. Every `/api/*` route requires
`Authorization: Bearer <token>`, checked against the `ENZO_API_TOKEN` Worker
secret. The dashboard at `/` is a static asset that prompts for the token once
and stores it in `localStorage`.

The legacy Sheets/Reminders tracker is fully decoupled; this Worker never
calls into it.

## Develop

```bash
cd apps/server
bun install
bun run dev          # wrangler dev on http://127.0.0.1:4318
```

Local dev uses a local D1 simulation and reads `ENZO_API_TOKEN` from
`.dev.vars` (gitignored; default `local-dev-token`). Apply migrations locally
with:

```bash
bunx wrangler d1 migrations apply enzo --local
```

Point the iOS Simulator at local dev with the `ENZO_API_BASE_URL` environment
variable.

## Deploy

```bash
bun run deploy
```

Schema changes go in `migrations/` and are applied with:

```bash
bunx wrangler d1 migrations apply enzo --remote
```

Rotate the token with `bunx wrangler secret put ENZO_API_TOKEN`, and mirror it
into `apps/ios/App/Secrets.swift`.

## History

The API originally ran as a local Bun server against native Postgres, exposed
over Tailscale. That data was migrated one-time into D1 (63 events, including
the initial import from the legacy Google Sheet). Soft deletes are still used;
`deleted_at` hides an event without destroying it.

## Trust model

- D1 and the Worker are the durable, always-on backend.
- A single shared bearer token is the authorization layer; there are no user
  accounts yet.
- Deletes are soft deletes.
