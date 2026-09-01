# Enzo app

Read [CONTEXT.md](CONTEXT.md) for the care-event domain language.

Postgres, accessed through `server/`, is the source of truth. The iOS app writes
through the local server interface and projects the resulting next-feed state to
ActivityKit and AlarmKit. Keep those projections reconciled with server state.

App mutations cross one legacy-sync seam: `server/legacy-sync.ts` sends an
idempotent mutation envelope to the private legacy CLI `sync-event` command.
That adapter mirrors the event to the Sheet and reasserts the shared Reminder.
Keep every other app module independent from legacy implementation details.
