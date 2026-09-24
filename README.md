# GrogLog

A fast, local-first iOS drink tracker built around cutting down. Log in one tap, see the day as a running total against yesterday and your usual, and taper with a daily budget that works from what you actually drink.

Written because Drinkaware's Drink Coach is low-friction but slow, allows one drink per type, can't graph, can't export, and treats a forgotten day the same as a dry one.

## Decisions worth knowing

- **Unlogged ≠ dry.** A day only counts as alcohol-free when you mark it. Gaps show as `?` in the calendar, stay out of averages, and are labelled `not_logged` in exports so an LLM doesn't read a blackout as a good day.
- **Days end at 5am** (configurable). The 1am pint belongs to the night it was part of.
- **A drink is what it is; size is how you had it.** A drink holds name, type and strength (Staropramen, beer, 5%). A Log-grid tile is a drink in a size at the price you usually pay; a log entry is a drink in a size at the price you actually paid. Fixing a drink's name or ABV fixes everything logged as it; prices are copied because they change. Sizes always come from the type — beers get pints, cans and bottles, never a wine glass. Generic drinks use Drinkaware's standard strengths (beer 4%, cider 4.5%, wine 12%, spirits 40%) and are editable.
- **The catalogue is a starting point, not a database.** UK brands with their usual serves at their label strengths; picking one copies it in as your own drink, editable from then on. A brand brewed at two strengths is two entries (`Sharp's Doom Bar` 4%, `Sharp's Doom Bar (bottle)` 4.3%) because a drink is one strength. Every serve carries a starting price on one convention: a pint, a glass or a measure is what a London bar charges, a can or a bottle what a supermarket does — except the Belgians, which are priced as a bar pours them, because that is how anyone drinks them. That is a fudge — the same bottle is £30 in a shop and £200 in a club — and it holds until prices know where you are. Most figures are looked up; the kinds that can't be are marked in `Catalog.swift`, since pubs price draught by tier rather than by brand, mainstream lager and cider don't sell as single cans here at all, and only one London Belgian bar publishes what it charges. Two ranges sit outside the convention because there is only one place to buy them: Aldi and Lidl's own labels at shop prices, and Wetherspoon's list at one Wetherspoon's — The Watch House in Lewisham — since the chain prices every pub separately.
- **The grid is yours.** Favourites (drink + size) plus anything logged that day, most recent first. Tap logs it; long-press picks a specific drink of the same type, overrides the size, stars it onto the grid, or logs several earlier. A tap never reshuffles the grid.
- **Charts show the shape, not just the total.** Day, week and month charts are running totals that step at each drink, so a heavy night is a steep climb. Progress charts smooth daily units over a few days against the budget smoothed the same way, so they read as a trend rather than a comb. Today is the exception: it's plotted as what's logged so far, on the "now" line, so the trend runs into the dot marking the day as it actually stands. A day inside its budget reads teal, just over amber, well over red.
- **Units as an item.** When you only know a total (another app, a night you didn't log), log "Units" directly.
- **Heart readings answer to the night before.** Overnight HRV, resting heart rate and heart rate while asleep are read from Health — whatever wrote them, a Garmin or a watch — and filed under the drinking day they followed, 8pm to 8pm on a 5am day end, so a heavy Friday's damage lands on Friday's bar and not Saturday's. Daytime HRV spot readings are left out. Heart rate while asleep takes only the readings inside an asleep stage, so time awake in the night doesn't count, and only those nights' heart rate is fetched — a watch writes one every minute or two for years. Everything Health holds is read, however far back, so the weekly bars carry on from before the log began. A night with no reading is missing, not zero, and a week's average needs three nights before it's drawn; a gap is crossed by a faint dashed line, which joins the readings either side and claims nothing about what's between. Weekly progress carries each night as it came, sleeping rate included since it's the nearest to the night itself, to show what one evening costs; Monthly progress and the weekly bars carry averages, because recovery from a run of them is slow and only shows over weeks — resting rate especially. Garmin Connect writes resting rate to Health but not HRV. Health labels every HRV as SDNN whatever the device measured, so the numbers compare with themselves, not with another brand's.
- **Spend can be set for a whole day.** A round-by-round price is a chore on a big night; set what the day cost and it stands in for the drinks' prices everywhere, until you clear it.

## Layout

| Tab | What for |
|---|---|
| Log | The picker for today. Search, tap, long-press, undo. |
| Calendar | History; tap a day to see or backfill it, long-press to mark it dry. |
| Day | Running units through the day vs yesterday and the week's average day, the day's budget draining, and what it cost. |
| Reports | Weekly and monthly progress (daily units against the budget, with the fortnight ahead — scroll and pinch — and heart readings when Health has them), sleep by stage against the evening before, this week and this month against earlier ones, weekly bars, streaks, spend. |
| Setup | Goal, drinks, day end, currency, export/import. |

Two widgets, both reading the same log: a Lock Screen accessory showing today against the budget that opens onto Log, and a Home Screen one whose tiles log a drink where they stand.

## Data

SQLite via [GRDB](https://github.com/groue/GRDB.swift), built to stay instant after years of heavy use:

- **Day totals are stored, entries are fetched by day.** Each `day` row holds a drinking day's units, kcal, cost, count, dry mark and any hand-set spend — a few hundred rows a year. Calendar, Reports, budgets, streaks and projections read only these. Individual `pour`s are indexed by day and fetched only for the days on screen.
- **Every write is one transaction through `Logbook`.** Log, undo, edit, mark dry, change a drink: the affected days are recomputed from their entries in the same transaction. Totals are always derived, never incremented, so they can't drift; `rebuild()` is the same arithmetic over everything.
- **Logging is an `AppIntent` too.** Shortcuts, the Action Button and widgets reach the same `Logbook` transaction as a tap on the grid, so there's no second write path to keep in step.
- **Screens observe the database.** `GRDBQuery` requests (`Queries.swift`) re-run after each commit, so every screen updates the moment a write lands, whoever made it. Tracking is by table, so a drink logged today re-runs every entries request in the app; a fetch that comes back unchanged isn't delivered, and charts and calendar cells sit on plain values so a commit that doesn't change what they show doesn't lay them out again.
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

Setup › **Copy to Health** mirrors drinks and calories into Apple Health as they're logged. Health counts standard drinks, not UK units — 17.7 ml of alcohol against 10 — so the figures are converted rather than handed over. It's a mirror and never a source: a changed day is rewritten whole from the log, so edits, undos and corrected strengths carry across and the copy can't drift; turning it off takes GrogLog's entries back out. A widget's tap logs in the widget's own process, which can't reach Health, so the app catches those days up when it next comes to the front.

Setup › **Heart readings from Health** and **Sleep from Health** read heart rate, HRV and sleep stages for Reports. They are separate because each is its own permission in Health and its own card's worth of screen. Reading only; nothing is written back. A night recorded by two devices takes the one that recorded more sleep, since adding them would double it.

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
