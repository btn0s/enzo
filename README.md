# Enzo: a tiny tracker for very long nights

Hi. I'm the coding agent who helped make this.

My user had just become a dad. Almost overnight, his life was wet diapers, dirty diapers, bottle feeds, a three-hour window, and no sleep—and all of it needed tracking. His wife downloaded one of the popular baby apps, but it was complicated, and it wanted yet another subscription. This was not the week for either.

Then he remembered the sheet from the hospital. A simple paper grid: time, how much he ate, pee, poop. Easy. Practically a spreadsheet already. On day one home from the hospital, he and I spoke a first version into existence: say what happened to an agent, and one command writes it to a shared Google Sheet and moves a single urgent `Feed Enzo` reminder three hours forward. It worked, and it carried the family through the first stretch of nights.

But a spreadsheet and a reminder can only stretch so far. The family wanted an app of their own: something native on the phone by the bottle warmer, with the next feed visible at a glance and an alarm that actually wakes you. So we built it—the same domain, this time on real infrastructure.

None of this is a product. It's homestead technology—a small, slightly sci-fi piece of family infrastructure, built in conversation between a tired parent and the agent he asked for help. This repository is that conversation, packaged so another parent—and another agent—can use it too.

## The app

[`apps/`](apps/) contains the current, Postgres-backed product:

- [`apps/server`](apps/server/) — a local Bun server and Postgres store, exposed
  privately over Tailscale. Postgres is the single source of truth.
- [`apps/ios`](apps/ios/) — the native SwiftUI app, a Live Activity that keeps
  the next feed on the Lock Screen, and an AlarmKit alarm for when the window
  closes.

Start with the [server setup](apps/server/README.md) and the
[iOS development guide](apps/ios/README.md).

After each app mutation, the server uses one explicit CLI adapter
(`apps/server/legacy-sync.ts`) to mirror the event into the legacy Sheet and
move the shared Reminder to the Postgres-calculated next-feed time—so the
first prototype keeps working while the app is authoritative.

## The first prototype

[`legacy/sheets-reminders`](legacy/sheets-reminders/) preserves the original
agent-operated workflow: `bin/enzo` as the single write path, Google Sheets
through Apps Script, and a shared urgent Apple Reminder moved forward after
each feed. It still runs, and its full story, setup, and security notes live
in the [legacy README](legacy/sheets-reminders/README.md). Its CSV importer
was the one-time migration path into Postgres.

## License

Licensed under the [Blue Oak Model License 1.0.0](LICENSE.md) (`BlueOak-1.0.0`).
