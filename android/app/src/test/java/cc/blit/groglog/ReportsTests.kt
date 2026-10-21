package cc.blit.groglog

import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Night
import cc.blit.groglog.model.Nights
import cc.blit.groglog.ui.reports.DayBar
import cc.blit.groglog.ui.reports.HeartLines
import cc.blit.groglog.ui.reports.HeartPoint
import cc.blit.groglog.ui.reports.HeartReading
import cc.blit.groglog.ui.reports.HeartScale
import cc.blit.groglog.ui.reports.Progress
import cc.blit.groglog.ui.reports.heartSummary
import cc.blit.groglog.ui.reports.niceTicks
import cc.blit.groglog.ui.reports.readout
import cc.blit.groglog.ui.reports.runningRange
import java.time.Instant
import java.time.temporal.ChronoUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** A night with no reading is missing, never zero: lines break there, and a dashed bridge claims nothing about it. */
class HeartLineTests {
    private val days = (0 until 6).map { DayKey(100 + it) }
    private val at = { day: DayKey -> day.number + 0.5 }

    @Test fun aMissingNightBreaksTheLineAndIsBridged() {
        val values = mapOf(100 to 50.0, 101 to 52.0, 103 to 48.0, 104 to 47.0, 105 to 49.0)
        val points = HeartPoint.line(HeartReading.HRV, days, at = at) { values[it.number] }
        val measured = points.filter { !it.bridge }
        assertEquals(5, measured.size)
        assertEquals(setOf(0, 1), measured.map { it.run }.toSet())
        val bridge = points.filter { it.bridge }
        assertEquals(listOf(101.5, 103.5), bridge.map { it.x })
        assertEquals(1, bridge.map { it.run }.distinct().size)
    }

    @Test fun aReadingAloneIsMarkedSoItCanBeDrawnAsADot() {
        val values = mapOf(100 to 50.0, 102 to 52.0, 103 to 51.0)
        val points = HeartPoint.line(HeartReading.RESTING, days, at = at) { values[it.number] }.filter { !it.bridge }
        assertEquals(listOf(true, false, false), points.map { it.alone })
    }

    @Test fun anOldReadingComesInFromTheLeftEdgeOnTheSameSlope() {
        // 40 at day 90, 50 at day 100's noon: the anchor at day 100's noon is 50, and at day 95.5's noon 45.
        val values = mapOf(90 to 40.0, 100 to 50.0)
        val line = HeartPoint.line(HeartReading.HRV, (95..100).map(::DayKey), before = DayKey(90), at = at) { values[it.number] }
        val anchor = line.first { it.bridge }
        assertEquals(95.5, anchor.x, 1e-9)
        assertEquals(45.0, anchor.value, 1e-9)
    }

    @Test fun theChosenReadingFallsBackToOneWithData() {
        val points = HeartPoint.line(HeartReading.RESTING, days, at = at) { 55.0 }
        assertEquals(HeartReading.RESTING, HeartPoint.drawn(HeartReading.HRV, points))
        assertNull(HeartPoint.drawn(HeartReading.HRV, emptyList()))
    }

    @Test fun aScaleFitsItsReadingsInsideTheUnitsChart() {
        val points = listOf(41.0, 63.0).mapIndexed { i, v -> HeartPoint(i.toDouble(), v, HeartReading.HRV, 0) }
        val scale = HeartScale.of(points, top = 20.0)!!
        assertEquals(35.0, scale.low, 0.0)
        assertEquals(70.0, scale.high, 0.0)
        assertTrue(points.all { scale.y(it.value) in 0.0..20.0 })
        assertEquals(listOf(40, 50, 60, 70), scale.ticks.map { it.second })
    }

    @Test fun gridlinesFallOnRoundNumbers() {
        assertEquals(listOf(0.0, 5.0, 10.0), niceTicks(11.5))
        assertEquals(listOf(0.0, 10.0, 20.0, 30.0, 40.0), niceTicks(46.0))
    }
}

@RunWith(RobolectricTestRunner::class)
class ProgressTests {
    private val goal = Goal(isEnabled = true, baselineWeekly = 70.0, start = Instant.now().minus(20, ChronoUnit.DAYS))

    private fun ledger(vararg rows: Day) = Ledger(rows.toList(), clock)

    @Test fun barsAreLoggedDaysAndAFadedToday() {
        val today = clock.today
        val ledger = ledger(Day((today - 3).number, units = 6.0, count = 2), Day((today - 2).number, isAlcoholFree = true), Day(today.number, units = 2.0, count = 1))
        val progress = Progress.of(ledger, goal, Nights(), HeartLines.NIGHTLY, 60, Instant.now())
        // Day -1 was never logged and has no bar; the dry day has an empty one.
        assertEquals(listOf(today - 3, today - 2, today), progress.bars.map { it.day })
        assertEquals(listOf(false, false, true), progress.bars.map { it.partial })
    }

    @Test fun theBudgetMeetsNowAndRunsOnAsThePlan() {
        val today = clock.today
        val progress = Progress.of(ledger(Day((today - 10).number, units = 6.0, count = 2)), goal, Nights(), HeartLines.NIGHTLY, 60, Instant.now())
        assertEquals(progress.behind.last(), progress.ahead.first())
        assertEquals(progress.now, progress.ahead.first().first, 1e-9)
        assertEquals((today + 14).number + 0.5, progress.ahead.last().first, 1e-9)
        assertTrue(progress.behind.dropLast(1).all { it.first <= progress.now })
    }

    @Test fun theHeldDaySaysWhetherItWasDryOrNeverLogged() {
        val today = clock.today
        val ledger = ledger(Day((today - 5).number, units = 6.0, count = 2), Day((today - 3).number, isAlcoholFree = true))
        assertEquals("Dry", readout(ledger, goal, (today - 3).number + 0.4).lines.first())
        assertEquals("Not logged", readout(ledger, goal, (today - 2).number + 0.9).lines.first())
        assertTrue(readout(ledger, goal, (today + 3).number + 0.5).lines.single().startsWith("Plan"))
        assertTrue(readout(ledger, Goal(), (today - 5).number + 0.5).lines.single().startsWith("6.0 u"))
    }

    @Test fun weeklyHeartLinesCarryEachNightAndMonthlyOnesTheWeekOfHrvAndEachNightOfRestingRate() {
        val today = clock.today
        val nights = Nights(((today - 20)..(today - 1)).associateWith { Night(hrv = 50.0, restingHR = 55.0 + it.number % 3, sleepingHR = 50.0) })
        val ledger = ledger(Day((today - 30).number, units = 6.0, count = 2))
        val nightly = Progress.of(ledger, goal, nights, HeartLines.NIGHTLY, 60, Instant.now()).hearts
        val monthly = Progress.of(ledger, goal, nights, HeartLines.MONTHLY, 120, Instant.now()).hearts
        assertEquals(HeartReading.entries.toSet(), nightly.map { it.reading }.toSet())
        assertFalse(monthly.any { it.reading == HeartReading.SLEEPING })
        // A week's average needs three nights, so the first two nights of readings have none.
        assertEquals(18, monthly.count { it.reading == HeartReading.HRV && !it.bridge })
        // Resting rate is every night as it came, not smoothed.
        val resting = monthly.filter { it.reading == HeartReading.RESTING && !it.bridge }
        assertEquals(20, resting.size)
        assertTrue(resting.all { it.value == 55.0 + (kotlin.math.floor(it.x).toInt() % 3) })
        assertEquals(", 7-night", HeartLines.MONTHLY.suffix(HeartReading.HRV))
        assertEquals("", HeartLines.MONTHLY.suffix(HeartReading.RESTING))
        // The caption says the same as the lines: HRV over the week, resting rate last night.
        val lastNight = today - 1
        val summary = heartSummary(nights, HeartLines.MONTHLY, lastNight).single().text
        assertEquals("HRV 50 ms over the last week · RHR ${(55.0 + lastNight.number % 3).toInt()} bpm last night", summary)
    }

    @Test fun theRunningTotalsReachBackToLastMonthAndThreeWeeks() {
        val range = runningRange(ledger())
        val today = clock.today
        assertTrue(range.start <= (today.monthStart - 1).monthStart)
        assertTrue(range.start <= clock.weekStart(today) - 21)
        assertEquals(today, range.endInclusive)
    }
}

/** What TalkBack says for a day's bar. */
class DayBarSpokenTests {
    private val day = DayKey.of(2026, 9, 19)

    @Test fun aDryDayIsAlcoholFreeNotNoughtUnits() {
        assertEquals("alcohol-free", DayBar(day, 0.0, partial = false, budget = null, dry = true).spoken)
        assertEquals("alcohol-free, budget 4.0, within budget", DayBar(day, 0.0, partial = false, budget = 4.0, dry = true).spoken)
    }

    @Test fun todayWithNothingIsNothingYet() {
        assertEquals("nothing yet", DayBar(day, 0.0, partial = true, budget = null).spoken)
        assertEquals("2.0 units so far", DayBar(day, 2.0, partial = true, budget = null).spoken)
    }
}
