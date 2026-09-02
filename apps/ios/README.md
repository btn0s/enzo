# Enzo iOS native-flow prototype

> **Throwaway prototype.** The question is whether a force-alarm + Live
> Activity + fast manual-entry loop is faster and calmer than opening a tracker.

## What this tests

- AlarmKit schedules a configurable next-feed alarm on iOS 26 with a per-device
  toggle, lead time, active-hours window, selected sound, and optional explicit
  “Remind me” interval. Alarms can also be skipped for an individual feed;
  acknowledging one prevents reconciliation from recreating it.
- A Live Activity and a home screen widget show the next-feed countdown; tapping either opens the app.
- A feed is one completed entry flow with milk, amount, and an intelligently defaulted time.
- The dashboard leads with the exact next-feed time; its countdown is supporting context.
- A bottom action bar puts Add feed and Add diaper one tap away.
- Manual entry uses compact bottom sheets with smart defaults. Diaper is one flow
  with independent Pee and Poop checkboxes, so either or both can be saved.
- The Today card shows age-aware goals for milk, feeds per day, and wet/dirty
  diapers, with a "How goals are calculated" sheet citing sources. Enzo's birth
  date and time are set in Settings (default August 28, 2026, 9 PM); the birth
  day is day 0. Volumes display in ounces by default, switchable to milliliters
  in Settings or per feed; the server always stores milliliters.

## General guidance encoded in the prototype

These are tracking references, not diagnoses or replacements for Enzo's clinician:

- [CDC formula feeding guidance](https://www.cdc.gov/infant-toddler-nutrition/formula-feeding/how-much-and-how-often.html) — 8–12 feeds per 24 hours in the first week (every 2–3 hours), 6–8 after.
- [Safer Care Victoria formula volumes](https://www.safercare.vic.gov.au/best-practice-improvement/clinical-guidance/neonatal/formula-feeding) — term neonates: 30, 60, 80, 100, 120, 150 mL/kg/day for each 24-hour band from birth.
- [American Academy of Pediatrics formula amounts](https://www.healthychildren.org/English/ages-stages/baby/formula-feeding/Pages/amount-and-schedule-of-formula-feedings.aspx) — 150–200 mL/kg/day once established (from 144 hours).
- [NHS early bottle-feeding and nappy guidance](https://elht.nhs.uk/application/files/7017/1957/8897/E0126_Early_Bottle_Feeding_V3_Sep23_UNICEF_statement_added_2.pdf) — pee minimums by day of life (1 on days 0–1, 2 on day 2, 3 on days 3–4, 5 on days 5–6, 6 from day 7) and one poop per day.

The daily milk goal is `mL/kg/day for current hours of age × current weight`;
the per-bottle target spreads it over the low end of the feed range.

The shared feed interval is set in Settings → Feed schedule (two hours by
default). Checkups stored in D1 record weight and anything the doctor changed —
bottle size, feed interval, feeds/day, daily milk, or pee/poop minimums. The
latest past checkup wins per field; blank fields fall back to guidance or the
shared feed-interval setting. The Today card and goals sheet label each number's
source. Pace icons compare today's count with the goal scaled to the time of
day. Guidance tables live in `App/DailyInsights.swift`.

## Generate and run

The API is the deployed Cloudflare Worker (see `apps/server`). Builds need
`App/Secrets.swift` (gitignored; see `App/Secrets.example.swift`) with the
Worker bearer token. Then:

```bash
cd apps/ios
xcodegen generate
open EnzoPrototype.xcodeproj
```

Both Simulator and device builds use `https://enzo-api.btn0s.workers.dev`;
override with the `ENZO_API_BASE_URL` environment variable (e.g. against
`wrangler dev` on port 4318).

## Known prototype compromises

- A single shared bearer token is the trust boundary; app accounts are not implemented yet.
- The Live Activity and widget open the app; neither uses an interactive
  `LiveActivityIntent` button.
- Offline outbox and physical-device signing are not implemented yet.
