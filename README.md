# GrogLog

A fast, local-first iOS drink tracker built around cutting down. Log in one tap, see the day as a running total against yesterday and your usual, and taper with a daily budget that works from what you actually drink.

Written because Drinkaware's Drink Coach is low-friction but slow, allows one drink per type, can't graph, can't export, and treats a forgotten day the same as a dry one.

## Decisions worth knowing

- **Unlogged ≠ dry.** A day only counts as alcohol-free when you mark it. Gaps show as `?` in the calendar, stay out of averages, and are labelled `not_logged` in exports so an LLM doesn't read a blackout as a good day.
- **Days end at 5am** (configurable). The 1am pint belongs to the night it was part of.
- **A drink is what it is; size is how you had it.** A drink holds name, type and strength (Staropramen, beer, 5%). A Log-grid tile is a drink in a size at the price you usually pay; a log entry is a drink in a size at the price you actually paid. Fixing a drink's name or ABV fixes everything logged as it; prices are copied because they change. Sizes always come from the type — beers get pints, cans and bottles, never a wine glass. Generic drinks use Drinkaware's standard strengths (beer 4%, cider 4.5%, wine 12%, spirits 40%) and are editable.
- **The grid is yours.** Favourites (drink + size) plus anything logged that day, most recent first. Tap logs it; long-press picks a specific drink of the same type, overrides the size, stars it onto the grid, or logs several earlier. A tap never reshuffles the grid.
- **Charts show the shape, not just the total.** Day, week and month charts are running totals that step at each drink, so a heavy night is a steep climb. Progress charts smooth daily units over a few days — today counting as it goes — against the budget smoothed the same way, so they read as a trend rather than a comb. A day inside its budget reads teal, just over amber, well over red.
- **Units as an item.** When you only know a total (another app, a night you didn't log), log "Units" directly.

## Layout

| Tab | What for |
|---|---|
| Log | The picker for today. Search, tap, long-press, undo. |
| Calendar | History; tap a day to see or backfill it, long-press to mark it dry. |
| Day | Running units through the day vs yesterday and the week's average day, plus the day's budget draining. |
| Reports | Weekly and monthly progress (smoothed daily units against the budget, with the fortnight ahead — scroll and pinch), this week and this month against earlier ones, weekly bars, streaks, spend. |
| Setup | Goal, drinks, day end, currency, export/import. |

## Data

SQLite via [GRDB](https://github.com/groue/GRDB.swift), built to stay instant after years of heavy use:

- **Day totals are stored, entries are fetched by day.** Each `day` row holds a drinking day's units, kcal, cost, count and dry mark — a few hundred rows a year. Calendar, Reports, budgets, streaks and projections read only these. Individual `pour`s are indexed by day and fetched only for the days on screen.
- **Every write is one transaction through `Logbook`.** Log, undo, edit, mark dry, change a drink: the affected days are recomputed from their entries in the same transaction. Totals are always derived, never incremented, so they can't drift; `rebuild()` is the same arithmetic over everything.
- **Screens observe the database.** `GRDBQuery` requests (`Queries.swift`) re-run after each commit, so every screen updates the moment a write lands, whoever made it.
- **Migrations are explicit and append-only** (`AppDatabase`). The database is never erased to change its schema.
- **Days are integers.** `DayKey` is days since 1970 with pure civil-date arithmetic; each entry stores the day it counted towards when logged, so timezones don't move old nights.
- `ScaleTests` loads three years at 20 drinks a day of one drink in one transaction, then times taps, a screen's worth of reads, and a full rebuild.

Records are plain structs: `Drink` (what it is), `Favourite` (a drink + size + usual price on the grid), `Pour` (a drink + size + price paid), `Day` (a day's totals); `Entry` joins a pour to its drink. `Ledger` is read-only maths over days, `Logbook` owns writes. Views take a `Ledger` and don't group data themselves.

## Export and import

Setup › Data exports:

- **Markdown** — a readable log for pasting into an LLM.
- **JSON backup** — everything, re-importable. Import merges: existing drinks, pours and days with drinks are never touched, so re-importing is safe.

The JSON import is lenient enough to hand-convert other apps' data — see [docs/IMPORT.md](docs/IMPORT.md).

Sync (iCloud via `CKSyncEngine`, or a server) is future work; every change already goes through `Logbook` as a transaction, which is where a change log would hook in.

## Building

```sh
mise install            # xcodegen
xcodegen generate
open GrogLog.xcodeproj
```

Requires Xcode 26+ / iOS 26. The app icon is rendered from the pint glyph by `scripts/render-icon.sh`. `scripts/shoot.sh <dir> [light|dark]` builds, launches in demo mode (`-demoMode YES`) and screenshots every tab (`-tab <name>` picks the starting tab). Debug builds have Setup › Developer › Demo mode, which swaps in an in-memory store of sample data and leaves your log alone.

Tests: `xcodebuild -scheme GrogLog -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`.
