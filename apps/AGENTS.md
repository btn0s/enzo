# Enzo app

Read [CONTEXT.md](CONTEXT.md) for the care-event domain language.

D1, accessed through the `server/` Cloudflare Worker, is the source of truth.
The iOS app writes through the Worker API with a bearer token and projects the
resulting next-feed state to ActivityKit and AlarmKit. Keep those projections
reconciled with server state.

The legacy Sheets/Reminders tracker is fully decoupled: no app module may call
into `legacy/` or depend on its implementation details.
