# GrogLog

A fast, local-first iOS drink tracker built around cutting down. Log in one tap, see the day as a running total against yesterday and your usual, and taper with a daily budget that works from what you actually drink.

Written because Drinkaware's Drink Coach is low-friction but slow, allows one drink per type, can't graph, can't export, and treats a forgotten day the same as a dry one.

## Decisions worth knowing

- **Unlogged ≠ dry.** A day only counts as alcohol-free when you mark it. Gaps show as `?` in the calendar, stay out of averages, and are labelled `not_logged` in exports so an LLM doesn't read a blackout as a good day.
- **Days end at 5am** (configurable). The 1am pint belongs to the night it was part of.
- **A drink is what it is; size is how you had it.** A drink holds name, type and strength (Staropramen, beer, 5%). A Log-grid tile is a drink in a size at the price you usually pay; a log entry is a drink in a size at the price you actually paid. Fixing a drink's name or ABV fixes everything logged as it; prices are copied because they change. Sizes always come from the type — beers get pints, cans and bottles, never a wine glass. Generic drinks use Drinkaware's standard strengths (beer 4%, cider 4.5%, wine 12%, spirits 40%) and are editable.
- **The grid is yours.** Favourites (drink + size) plus anything logged that day, most recent first. Tap logs it; long-press picks a specific drink of the same type, overrides the size, stars it onto the grid, or logs several earlier. A tap never reshuffles the grid.
- **Units as an item.** When you only know a total (another app, a night you didn't log), log "Units" directly.

## Layout

| Tab | What for |
|---|---|
| Log | The picker for today. Search, tap, long-press, undo. |
| Calendar | History; tap a day to see or backfill it, long-press to mark it dry. |
| Day | Running units through the day vs yesterday and the month's average day, plus the day's budget draining. |
| Reports | Monthly progress (daily units vs the budget, with the fortnight ahead), this month vs last (cumulative), weekly bars, streaks, spend. |
| Setup | Goal, drinks, day end, currency, export/import. |

Code: `Model/` holds pure logic — `DayClock` (drinking days), `Goal` (taper settings), `Ledger` (read-only view of everything logged; budgets, streaks, curves, projections) — plus SwiftData models: `Drink` (what it is), `Favourite` (a drink + size on the grid), `Pour` (a drink + size + price, logged), `AlcoholFreeDay`. Views take a `Ledger` and don't group data themselves.

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
