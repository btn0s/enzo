# Enzo iOS native-flow prototype

> **Throwaway prototype.** The question is whether a force-alarm + Live
> Activity + voice-first loop is faster and calmer than opening a tracker.

## What this tests

- AlarmKit schedules the next feeding alarm on iOS 26.
- A Live Activity shows the next-feed countdown and deep-links into feeding.
- A feed is one completed entry flow with milk, amount, and an intelligently defaulted time.
- Tap-to-talk or hold-to-talk turns short phrases into the same feed/diaper API calls.
- Manual controls remain available, but intentionally secondary.
- The dashboard leads with the exact next-feed time; its countdown is supporting context.
- A native Liquid Glass AI-style composer keeps text, microphone dictation, and
  send within thumb reach. A separate `+` menu opens the manual Feed and Diaper flows.
- Manual entry uses compact bottom sheets with smart defaults. Diaper is one flow
  with independent Pee and Poop checkboxes, so either or both can be saved.
- The scrolling dashboard includes age-aware reference insights for feeding cadence,
  feeds per day, formula amount, and wet/dirty diapers. Enzo's birth date is
  currently configured as August 28, 2026.

## General guidance encoded in the prototype

These are tracking references, not diagnoses or replacements for Enzo's clinician:

- [CDC formula feeding guidance](https://www.cdc.gov/infant-toddler-nutrition/formula-feeding/how-much-and-how-often.html)
- [American Academy of Pediatrics formula amounts](https://www.healthychildren.org/English/ages-stages/baby/formula-feeding/Pages/amount-and-schedule-of-formula-feedings.aspx)
- [NHS early bottle-feeding and nappy guidance](https://elht.nhs.uk/application/files/7017/1957/8897/E0126_Early_Bottle_Feeding_V3_Sep23_UNICEF_statement_added_2.pdf)

The first-week reference is 8–12 formula feeds per 24 hours and 30–60 mL
per feed. Wet-diaper minimums rise by day of life (1 on day 1, 2 on day 2,
3 on days 3–4, 5 on days 5–6, and 6 from day 7). The prototype uses one dirty
diaper per day as the early bottle-feeding reference. All thresholds should
remain configurable as Enzo grows and as his clinician gives individual advice.

Example phrases:

- “Poop at 9:23 p.m.”
- “Pee and poop now.”
- “Formula feed, 30 milliliters.”
- “Feed at 9:23 p.m., 30 milliliters.”

## Generate and run

Native Postgres and the local Bun API must be running on port 4318. Then:

```bash
cd apps/ios
xcodegen generate
open EnzoPrototype.xcodeproj
```

The Simulator build uses `http://127.0.0.1:4318`. A device build uses the
private Tailscale URL on port 8443.

## Known prototype compromises

- Speech parsing is deterministic and intentionally narrow; no LLM is needed
  for the supported commands.
- The Mac-hosted API uses Tailscale as its trust boundary; app accounts are not implemented yet.
- The Live Activity deep-links into the app; it does not yet use an interactive
  `LiveActivityIntent` button.
- Offline outbox and physical-device signing are not implemented yet.
