# Import format

Setup › Data › Import backup takes GrogLog's own JSON backup, or a hand-written file in the same shape. Only `days[].date` and `days[].status` are required, so an LLM can turn screenshots or PDFs from another app, such as Drink Coach, into an import.

Import merges: a day that already has drinks is left alone, and pours with an `id` already present are skipped. Re-importing the same file is safe.

## Minimal: daily totals

When all you have is a total per day, give `units` (and optionally `kcal` and `cost`). Each becomes a single "Units" entry at 20:00.

```json
{
  "days": [
    { "date": "2026-09-12", "status": "drank", "units": 30.6, "kcal": 2696, "cost": 42.00 },
    { "date": "2026-09-11", "status": "alcohol_free" }
  ]
}
```

## With drinks

List `pours` instead. A pour with `volumeMl` is a drink (`abv` defaults from `category`); a pour with only `units` is a bare unit count. `time` is ISO 8601; without it, pours are spaced 30 minutes apart from 20:00.

```json
{
  "days": [
    {
      "date": "2026-09-13",
      "status": "drank",
      "pours": [
        { "name": "Stella Artois", "category": "beer", "vessel": "can", "volumeMl": 440, "abv": 4.6, "time": "2026-09-13T19:05:00+01:00" },
        { "name": "Henry Westons Vintage", "category": "cider", "vessel": "bottle", "volumeMl": 500, "abv": 8.2 }
      ]
    }
  ]
}
```

## Fields

- `date`: `yyyy-MM-dd`, the drinking day (a drink at 1am belongs to the previous date).
- `status`: `drank`, `alcohol_free`, or `not_logged` (ignored). Only explicit `alcohol_free` marks a day dry.
- `category`: `beer`, `stout`, `cider`, `redWine`, `whiteWine`, `rose`, `bubbles`, `spirit`, `alcopop`, `cocktail`, `fortified`, `units`.
- `vessel`: `pint`, `half`, `can`, `bottle`, `wineBottle`, `wineGlass`, `flute`, `shot`, `tumbler`, `coupe`.
- `spentByHand`: the day's spend entered by hand, standing in for what its drinks cost. GrogLog's own backups carry it; leave it out and `cost` is taken from the pours.
- Top-level `dayStartsAtHour`, `currency` and `goal` restore settings when present; leave them out to keep yours.

## Prompt for converting screenshots

> Convert these drink-tracker screenshots into GrogLog import JSON as described in docs/IMPORT.md. One entry per visible day. Use `alcohol_free` only for days the app explicitly marks as alcohol-free; skip days with nothing shown. Copy units, calories and cost exactly. Output only the JSON.
