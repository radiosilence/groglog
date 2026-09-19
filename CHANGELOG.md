# Changelog

## Unreleased

- The long-press sheet puts size, how many and when first: with 200-odd brands below, they were a long scroll away.
- Number pads get a Done button. Units, strength, goal amounts and price had no way to put the keyboard away.
- The day rollover holds on the nights the clocks change: for an hour each changeover, a drink could land on the wrong side of "day ends at".
- Hiding a drink takes it off the Log grid and out of search, not just the long-press sheet. It still shows on a day it was had.
- The goal is edited as a draft, saved on Done and discarded on Cancel, from one sheet everywhere. Setup shows a summary row rather than the editor inline, where every keystroke was written straight to settings.
- Marking a day dry buzzes; un-marking it no longer does.
- Log tiles are buttons to VoiceOver, with the long-press sheet as an "Options" action.
- The UK catalogue goes from about 90 brands to about 220, and every strength is now the current UK label figure rather than one written from memory. Corrections worth knowing: Carling is 4% (not 3.7%), Carlsberg 3.4%, Kronenbourg 1664 4.6%, Grolsch 3.4%, Tanqueray 41.3%, Malibu 18%, Pimm's 22%. A brand brewed at two strengths is now two entries — `Fuller's London Pride` at 4.1% and `Fuller's London Pride (bottle)` at 4.7% — so a bottle of ale doesn't quietly log as its cask figure.
- Reports leads with Weekly progress and Monthly progress — the same chart over different spans — both scrollable and pinchable, with today banded.
- This week joins This month: the running total by drink time against the last three weeks and the week's budget.
- The Day chart compares against the week before rather than the month.
- Logging a drink plays a pour: the tile squishes, the glass fills (head and all), "+units" floats up and the count pops.
- Storage moved from SwiftData to SQLite (GRDB). Every change is a single transaction and screens update the moment it commits — no more lag after a burst of logging. Three years at 20 drinks a day imports in about 1.5 s; a tap takes about 1 ms.
- Restoring a backup onto a fresh install matches drinks by name and type, so the built-in generics aren't doubled.
- Stays fast with years of history: screens read per-day totals and fetch individual drinks only for the days shown; every change recomputes just the days it touches. Drinking days are fixed when logged, so timezone changes don't move them.
- Debug builds get a Demo mode that swaps in sample data without touching your log.
- Drinks are now separate from sizes: one Staropramen covers the 440 can and the 660 bottle. Log tiles and entries are a drink + size + price; sizes are limited to what suits the type. Existing data was folded in place (brands saved at several sizes became one drink; the per-size generics became Beer, Cider, … at Drinkaware's standard strengths).
- Long-press lists one row per drink of the same type, with a size override and a star to pin that drink + size to the grid. Spirits come as 25 ml or 35 ml singles or a 70 cl bottle.
- Logged drinks reference their drink instead of copying it: edits to name, type or strength apply to everything logged as it, while each entry keeps its own time, size and price. "Save as new drink" for when the drink itself changed; drinks with history can only be hidden.
- The Log grid shows anything logged that day as well as generics and favourites. A tap no longer re-sorts it under your thumb; a drink picked from the long-press sheet or search jumps to the front.
- Price entry fixed: typing 1, 5, 0 reads £0.01, £0.15, £1.50.
- Reports opens with **Monthly progress**: what you drank and your budget as 7-day rolling averages over four weeks, with the taper ahead.
- Dynamic budgets look back past gaps to the last logged day (up to four weeks) and show no budget rather than inventing one when there's no history.

- Budget modes are now scheduled or **dynamic tapering**: each day's budget is the cut applied to your average over the chosen period (yesterday, last week, …), so falling behind never demands a sudden drop.
- Projected dates for reaching your target and for dropping under 1 unit a day, in the goal editor, Reports and the Markdown export.
- Prices are typed like a banking app (1-6-0 → £1.60). Editors work on a local draft saved on Done, so typing no longer lags; Cancel now discards.
- Can, bottle and wine-bottle icons are drawn to size; generic "Big can/bottle" tiles are just "Can/Bottle of beer".
- App icon.

- First version: one-tap logging with generics, favourites and a UK brand catalogue; bare "Units" entries; calendar that separates dry from unlogged days; running-total day chart against yesterday and the month's average; tapering budget that works from recent drinking ("from today") or a fixed schedule, with withdrawal-safety warnings; monthly progress, month-vs-month and weekly reports; Markdown and JSON export; lenient JSON import for other apps' data.
