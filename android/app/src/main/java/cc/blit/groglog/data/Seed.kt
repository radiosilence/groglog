package cc.blit.groglog.data

import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Favourite
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Night
import cc.blit.groglog.model.Nights
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.Sleep
import cc.blit.groglog.model.Vessel
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random
import cc.blit.groglog.model.Goal
import kotlin.math.roundToInt

object Seed {
    /**
     * The demo's goal over `sample`'s log: a taper begun two weeks ago, from what the sample's first four weeks averaged
     * rounded to a whole unit a day (as "Use my last 4 weeks" sets it), so Reports and the Day tab show a budget part
     * way down rather than one begun this morning or one already run to nothing.
     */
    fun demoGoal(ledger: Ledger, goal: Goal): Goal {
        val first = ledger.firstDay ?: return goal
        val baseline = ledger.weeklyAverage(first..(first + 27))?.let { (it / 7).roundToInt() * 7.0 } ?: goal.baselineWeekly
        return goal.copy(start = ledger.clock.start(ledger.today - 14), baselineWeekly = baseline)
    }

    /**
     * Sample history for demo data. The current month shows a heavy first week, a failed dry spell, a binge starting
     * at 5am on wine, then a taper of beers starting later each evening. Earlier months show a steady baseline.
     */
    suspend fun sample(logbook: Logbook, days: Int = 120) {
        val clock = logbook.clock
        val today = clock.today
        val thisMonth = today.monthStart
        val dryRun = 6..11
        val binge = 12..13
        val taperFrom = 14
        val rng = Random(42)
        fun Random.between(from: Double, to: Double) = nextDouble(from, to)

        logbook.bulk { rows ->
            val beers = listOf(
                favourite("Stella Artois", DrinkCategory.BEER, 4.6, Vessel.CAN, 440.0, 1.75, logbook),
                favourite("Gipsy Hill Hepcat", DrinkCategory.BEER, 4.6, Vessel.PINT, 568.0, 6.50, logbook),
            )
            val heavy = beers + favourite("Henry Westons Vintage", DrinkCategory.CIDER, 8.2, Vessel.BOTTLE, 500.0, 2.75, logbook)
            val wine = favourite("Rioja", DrinkCategory.RED_WINE, 13.5, Vessel.WINE_GLASS, 250.0, 6.50, logbook)

            val touched = mutableSetOf<DayKey>()
            for (offset in days downTo 1) {
                val day = today - offset
                val date = day.components.day
                val inThisMonth = day.monthStart == thisMonth
                val onTheWine = inThisMonth && date in binge
                // How far into the taper, once it starts.
                val taper = if (inThisMonth && date >= taperFrom) {
                    min(1.0, (date - taperFrom).toDouble() / max(1, today.components.day - taperFrom))
                } else {
                    0.0
                }

                // Yesterday is always an evening out, so a screenshot of it has a day to show.
                val yesterday = offset == 1
                if (inThisMonth && date in dryRun && !yesterday) {
                    rows.save(Day(day.number, isAlcoholFree = true))
                    continue
                }
                val dryChance = if (taper > 0) 0.1 + taper * 0.3 else 0.08
                if (!onTheWine && rng.nextDouble() < dryChance && !yesterday) {
                    rows.save(Day(day.number, isAlcoholFree = true))
                    continue
                }
                if (!inThisMonth && rng.nextDouble() < 0.05 && !yesterday) continue

                // The taper sets the level; the noise is small.
                val target = when {
                    onTheWine -> rng.between(42.0, 48.0)
                    taper > 0 -> (30 - taper * 22) * rng.between(0.9, 1.1)
                    else -> rng.between(28.0, 38.0)
                }
                // The binge starts at first light; on the taper the first drink creeps later each evening.
                val opening = if (onTheWine) rng.between(0.2, 1.0) else rng.between(8.0, 10.0) + taper * 5
                var time = clock.start(day).plusMillis((opening * 3_600_000).toLong())
                var total = 0.0
                while (total < target) {
                    val serve = if (onTheWine && rng.nextInt(10) < 7) wine else (if (taper > 0) beers else heavy).random(rng)
                    rows.insert(Pour(drinkId = serve.drink.id, timestamp = time, day = day.number, vessel = serve.vessel, volumeMl = serve.volumeMl, price = serve.price))
                    total += serve.units
                    val gap = when {
                        onTheWine -> rng.between(20.0, 30.0)
                        taper > 0 -> rng.between(35.0, 65.0)
                        else -> rng.between(25.0, 45.0)
                    }
                    time = time.plusMillis((gap * 60_000).toLong())
                }
                touched += day
            }
            touched
        }
    }

    /**
     * Sample watch readings that respond to the log: a heavy night lowers the next morning's HRV and raises resting
     * rate, and a run of them shifts the baseline, so a dry week shows as recovery. Includes a gap of a few weeks where
     * the watch stopped syncing.
     */
    fun nights(ledger: Ledger, days: Int = 150): Nights {
        val rng = Random(7)
        fun between(from: Double, to: Double) = rng.nextDouble(from, to)
        val today = ledger.today
        val units = { day: DayKey -> ledger.totals(day).units }
        val byDay = LinkedHashMap<DayKey, Night>()
        for (day in (today - days)..(today - 1)) {
            // Occasional nights off the wrist.
            if (rng.nextDouble() < 0.06 || day in (today - 75)..(today - 40)) continue
            val week = ((day - 6)..day).sumOf(units) / 7
            byDay[day] = Night(
                hrv = 64 - units(day) * 0.45 - week * 0.35 + between(-4.0, 4.0),
                restingHR = 51 + units(day) * 0.12 + week * 0.22 + between(-1.5, 1.5),
                sleepingHR = 48 + units(day) * 0.35 + week * 0.1 + between(-1.5, 1.5),
                // Drinking shortens the night slightly, mostly at the expense of REM.
                sleep = Sleep(
                    deep = (1.4 - units(day) * 0.01 + between(-0.2, 0.2)) * 3600,
                    core = (4 - units(day) * 0.01 + between(-0.4, 0.4)) * 3600,
                    rem = max(0.2, 1.8 - units(day) * 0.04 + between(-0.2, 0.2)) * 3600,
                    awake = (0.3 + units(day) * 0.02 + between(0.0, 0.2)) * 3600,
                ),
            )
        }
        return Nights(byDay)
    }

    private suspend fun favourite(name: String, category: DrinkCategory, abv: Double, vessel: Vessel, ml: Double, price: Double, logbook: Logbook): Serve {
        val rows = logbook.rows
        val drink = logbook.findOrCreate(name, category, abv, vessel, ml).copy(price = price)
        rows.update(drink)
        if (rows.favourite(drink.id, vessel.raw, ml) == null) {
            rows.insert(Favourite(drinkId = drink.id, vessel = vessel, volumeMl = ml, price = price))
        }
        return Serve(drink, vessel, ml, price)
    }
}
