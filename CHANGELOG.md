# Changelog

## Unreleased

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
