# GrogLog

A fast, local-first iOS drink tracker built around cutting down. Log in one tap, see the day as a running total against yesterday and your usual, and taper with a daily budget that works from what you actually drink.

Written because Drinkaware's Drink Coach is low-friction but slow, allows one drink per type, can't graph, can't export, and treats a forgotten day the same as a dry one.

## Decisions worth knowing

- **Unlogged ≠ dry.** A day only counts as alcohol-free when you mark it. Gaps show as `?` in the calendar, stay out of averages, and are labelled `not_logged` in exports so an LLM doesn't read a blackout as a good day.
- **Days end at 5am** (configurable). The 1am pint belongs to the night it was part of.
- **A logged drink is a reference, not a copy.** Name, type and strength live on the drink, so fixing a typo or an ABV fixes everything logged as it. Each pour keeps only what's particular to it: when, the size poured, and the price paid (prices change). If a drink genuinely changes, "Save as new drink". Drinks with history can be hidden, not deleted.
- **The budget tapers from reality by default.** "Dynamic tapering" sets each day's budget X% under your average for the chosen period (yesterday, last week, …), so falling behind a plan never demands a sudden drop. Sudden drops from heavy drinking risk withdrawal; the goal editor warns above a 10%/day cut and, around 15+ units/day, suggests getting support. A fixed schedule is available if you want one.
- **Generics first, brands a long-press away.** Tap "Pint of beer" and you're done. Long-press to pick the specific brand (yours, or ~90 common UK drinks), a size, a time, or several at once. The main grid is generics, starred brands and anything logged that day, most recent first. A tap never reshuffles it; a long-press pick jumps to the front.
- **Units as an item.** When you only know a total (another app, a night you didn't log), log "Units" directly.

## Layout

| Tab | What for |
|---|---|
| Log | The picker for today. Search, tap, long-press, undo. |
| Calendar | History; tap a day to see or backfill it, long-press to mark it dry. |
| Day | Running units through the day vs yesterday and the month's average day, plus the day's budget draining. |
| Reports | Monthly progress (daily units vs the budget, with the fortnight ahead), this month vs last (cumulative), weekly bars, streaks, spend. |
| Setup | Goal, drinks, day end, currency, export/import. |

Code: `Model/` holds pure logic — `DayClock` (drinking days), `Goal` (scheduled taper), `Ledger` (read-only view of everything logged; budgets, streaks, curves) — plus SwiftData models. Views take a `Ledger` and don't group data themselves.

## Data

Local SwiftData store. Setup › Data exports:

- **Markdown** — a readable log for pasting into an LLM.
- **JSON backup** — everything, re-importable. Import merges: existing drinks, pours and days with drinks are never touched, so re-importing is safe.

The JSON import is lenient enough to hand-convert other apps' data — see [docs/IMPORT.md](docs/IMPORT.md).

The models follow CloudKit's rules (defaults on every property, no unique constraints), so iCloud sync is a configuration change rather than a migration.

## Building

```sh
mise install            # xcodegen
xcodegen generate
open GrogLog.xcodeproj
```

Requires Xcode 26+ / iOS 26. The app icon is rendered from the pint glyph by `scripts/render-icon.sh`. `scripts/shoot.sh <dir> [light|dark]` builds, launches with sample data (`-demo`) and screenshots every tab (`-tab <name>` picks the starting tab). Debug builds have Setup › Developer › Load sample data.

Tests: `xcodebuild -scheme GrogLog -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`.
