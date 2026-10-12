package cc.blit.groglog

import cc.blit.groglog.data.Logbook
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.Taper
import cc.blit.groglog.model.Vessel
import java.time.Instant
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.measureTime
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Years of heavy logging must not slow down a tap, a screen or an import. Three years at 20 drinks a day, all of one
 * drink: the worst case for anything that scales with a drink's history.
 */
@RunWith(RobolectricTestRunner::class)
class ScaleTests {
    @Test fun threeYearsOfHeavyLoggingStaysFast() = runBlocking {
        val clock = DayClock(5)
        val logbook = Logbook(database(), clock)
        val drink = Drink(name = "Stella Artois", category = DrinkCategory.BEER, abv = 4.6, vessel = Vessel.CAN, volumeMl = 440.0)
        logbook.add(drink)
        val today = clock.today

        // A whole history arriving at once, as from a backup: one transaction.
        val bulk = measureTime {
            logbook.bulk { rows ->
                val touched = mutableSetOf<DayKey>()
                for (offset in 1..3 * 365) {
                    val day = today - offset
                    val start = clock.start(day).plusSeconds(12 * 3600)
                    for (n in 0 until 20) {
                        rows.insert(Pour(drinkId = drink.id, timestamp = start.plusSeconds(n * 900L), day = day.number, vessel = Vessel.CAN, volumeMl = 440.0, price = 2.0))
                    }
                    touched += day
                }
                touched
            }
        }
        assertEquals(3 * 365 * 20, logbook.rows.pourCount())

        // The common mutations, several times over, timed individually: log, undo, edit.
        val taps = mutableListOf<Duration>()
        repeat(5) { taps += measureTime { logbook.log(Serve(drink), listOf(Instant.now())) } }
        val todays = entries(logbook, today..today)
        taps += measureTime { logbook.delete(todays[0].pour) }
        taps += measureTime { logbook.update(todays[1].pour, Instant.now(), Vessel.PINT, 568.0, 5.0) }

        // A full screen's worth of reads and maths: every day's totals, budgets, weeks, the day chart's month.
        val screens = measureTime {
            val ledger = Ledger(logbook.rows.days(), clock)
            // A year in, so the taper is asked for real: started today, every budget is the baseline and the maths is free.
            val goal = Goal(isEnabled = true, taper = Taper.DYNAMIC, start = clock.start(today - 365))
            for (offset in 0 until 120) ledger.dailyBudget(today - offset, goal)
            for (offset in 0 until 28) for (back in 0 until 7) ledger.dailyBudget(today - offset - back, goal)
            for (week in 0 until 52) ledger.week(clock.weekStart(today) - 7 * week, goal)
            ledger.projection(goal)
            ledger.longestDryStreak((today - 365)..today)
            val month = ledger.weekBefore(today)
            val entries = entries(logbook, month.start..today)
            ledger.cumulative(entries, today)
            ledger.averageCumulative(entries, month)
        }

        val rebuild = measureTime { logbook.rebuild() }

        println("scale: bulk $bulk, taps $taps, screens $screens, rebuild $rebuild")
        // The limits are iOS's, with room for Robolectric's SQLite on a laptop. A shared CI runner is several times
        // slower and less consistent, so it gets four times the room, which is still far below the orders of magnitude
        // a real regression costs.
        val room = (if (System.getenv("CI") == null) 1.0 else 4.0) * 2
        assertTrue("bulk $bulk", bulk < 3.seconds * room)
        assertTrue("taps $taps", taps.all { it < 30.milliseconds * room })
        assertTrue("screens $screens", screens < 250.milliseconds * room)
        assertTrue("rebuild $rebuild", rebuild < 3.seconds * room)
    }
}
