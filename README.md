# GrogLog

A fast, local-first iOS drink tracker built around cutting down. Log in one tap, see the day as a running total against yesterday and your usual, and taper with a daily budget that works from what you actually drink.

Written because Drinkaware's Drink Coach is low-friction but slow, allows one drink per type, can't graph, can't export, and treats a forgotten day the same as a dry one.

## Decisions worth knowing

- **Unlogged ≠ dry.** A day only counts as alcohol-free when you mark it. Gaps show as `?` in the calendar, stay out of averages, and are labelled `not_logged` in exports so an LLM doesn't read a blackout as a good day.
- **Days end at 5am** (configurable). The 1am pint belongs to the night it was part of.
- **A drink is what it is; size is how you had it.** A drink holds name, type and strength (Staropramen, beer, 5%). A Log-grid tile is a drink in a size at the price you usually pay; a log entry is a drink in a size at the price you actually paid. Fixing a drink's name or ABV fixes everything logged as it; prices are copied because they change. Sizes always come from the type — beers get pints, cans and bottles, never a wine glass. Generic drinks use Drinkaware's standard strengths (beer 4%, cider 4.5%, wine 12%, spirits 40%) and are editable.
- **The catalogue is a starting point, not a database.** UK brands with their usual serves at their label strengths; picking one copies it in as your own drink, editable from then on. A brand brewed at two strengths is two entries (`Sharp's Doom Bar` 4%, `Sharp's Doom Bar (bottle)` 4.3%) because a drink is one strength. Every serve carries a starting price on one convention: a pint, a glass or a measure is what a London bar charges, a can or a bottle what a supermarket does. That is a fudge — the same bottle is £30 in a shop and £200 in a club — and it holds until prices know where you are. Most figures are looked up; the two kinds that can't be are marked in `Catalog.swift`, since pubs price draught by tier rather than by brand, and mainstream lager and cider don't sell as single cans here at all.
- **The grid is yours.** Favourites (drink + size) plus anything logged that day, most recent first. Tap logs it; long-press picks a specific drink of the same type, overrides the size, stars it onto the grid, or logs several earlier. A tap never reshuffles the grid.
- **Charts show the shape, not just the total.** Day, week and month charts are running totals that step at each drink, so a heavy night is a steep climb. Progress charts smooth daily units over a few days against the budget smoothed the same way, so they read as a trend rather than a comb. Today counts for as much of a day as has gone, so a morning doesn't drag the trend down; the dot on the "now" line is the day as it actually stands. A day inside its budget reads teal, just over amber, well over red.
- **Units as an item.** When you only know a total (another app, a night you didn't log), log "Units" directly.
- **Spend can be set for a whole day.** A round-by-round price is a chore on a big night; set what the day cost and it stands in for the drinks' prices everywhere, until you clear it.

## Layout

| Tab | What for |
|---|---|
| Log | The picker for today. Search, tap, long-press, undo. |
| Calendar | History; tap a day to see or backfill it, long-press to mark it dry. |
| Day | Running units through the day vs yesterday and the week's average day, the day's budget draining, and what it cost. |
| Reports | Weekly and monthly progress (smoothed daily units against the budget, with the fortnight ahead — scroll and pinch), this week and this month against earlier ones, weekly bars, streaks, spend. |
| Setup | Goal, drinks, day end, currency, export/import. |

Two widgets, both reading the same log: a Lock Screen accessory showing today against the budget that opens onto Log, and a Home Screen one whose tiles log a drink where they stand.

## Data

SQLite via [GRDB](https://github.com/groue/GRDB.swift), built to stay instant after years of heavy use:

- **Day totals are stored, entries are fetched by day.** Each `day` row holds a drinking day's units, kcal, cost, count, dry mark and any hand-set spend — a few hundred rows a year. Calendar, Reports, budgets, streaks and projections read only these. Individual `pour`s are indexed by day and fetched only for the days on screen.
- **Every write is one transaction through `Logbook`.** Log, undo, edit, mark dry, change a drink: the affected days are recomputed from their entries in the same transaction. Totals are always derived, never incremented, so they can't drift; `rebuild()` is the same arithmetic over everything.
- **Logging is an `AppIntent` too.** Shortcuts, the Action Button and widgets reach the same `Logbook` transaction as a tap on the grid, so there's no second write path to keep in step.
- **Screens observe the database.** `GRDBQuery` requests (`Queries.swift`) re-run after each commit, so every screen updates the moment a write lands, whoever made it.
- **The log lives in the app group**, not the app's own container: a widget is a separate process and sees only what's shared. A log written before there were widgets moves across on first launch, its write-ahead log folded in first so one move carries everything; if the move fails the old file is still the log.
- **Migrations are explicit and append-only** (`AppDatabase`). The database is never erased to change its schema.
- **Days are integers.** `DayKey` is days since 1970 with pure civil-date arithmetic; each entry stores the day it counted towards when logged, so timezones don't move old nights.
- `ScaleTests` loads three years at 20 drinks a day of one drink in one transaction, then times taps, a screen's worth of reads, and a full rebuild.

Records are plain structs: `Drink` (what it is), `Favourite` (a drink + size + usual price on the grid), `Pour` (a drink + size + price paid), `Day` (a day's totals); `Entry` joins a pour to its drink. `Ledger` is read-only maths over days, `Logbook` owns writes. Views take a `Ledger` and don't group data themselves.

## Export and import

Setup › Data exports:

- **Markdown** — a readable log for pasting into an LLM.
- **JSON backup** — everything, re-importable. Import merges: existing drinks, pours and days with drinks are never touched, so re-importing is safe.

The JSON import is lenient enough to hand-convert other apps' data — see [docs/IMPORT.md](docs/IMPORT.md).

Setup › **Copy to Health** mirrors drinks and calories into Apple Health as they're logged. Health counts standard drinks, not UK units — 17.7 ml of alcohol against 10 — so the figures are converted rather than handed over. It's a mirror and never a source: a changed day is rewritten whole from the log, so edits, undos and corrected strengths carry across and the copy can't drift; turning it off takes GrogLog's entries back out.

Sync (iCloud via `CKSyncEngine`, or a server) is future work; every change already goes through `Logbook` as a transaction, which is where a change log would hook in.

## Building

```sh
mise install            # xcodegen
xcodegen generate
open GrogLog.xcodeproj
```

Requires Xcode 26+ / iOS 26. The app icon is rendered from the pint glyph by `scripts/render-icon.sh`. `scripts/shoot.sh <dir> [light|dark]` builds, launches in demo mode (`-demoMode YES`) and screenshots every tab (`-tab <name>` picks the starting tab). Debug builds have Setup › Developer › Demo mode, which swaps in an in-memory store of sample data and leaves your log alone.

`scripts/phone.sh [Debug|Release]` builds, installs and launches on the connected iPhone; installing over the app keeps its data.

Tests: `xcodebuild -scheme GrogLog -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`.
