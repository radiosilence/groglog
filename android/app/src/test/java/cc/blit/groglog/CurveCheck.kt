package cc.blit.groglog

import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Taper
import java.time.ZoneOffset
import kotlin.math.abs
import kotlin.math.max
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A stepped taper from 30 a day should change pace twice on the way down: 4 days, then 3, then 1. The first change is
 * a 29% steepening and the second a threefold one, so the first is easy to miss on the curve.
 */
class SteppedCurveTests {
    @Test fun aThirtyADayPlanChangesPaceTwice() {
        val utc = DayClock(5, ZoneOffset.UTC)
        val ledger = Ledger(emptyList(), utc)
        val first = DayKey.of(2026, 9, 18)
        val goal = Goal(isEnabled = true, taper = Taper.DYNAMIC, baselineWeekly = 30 * 7.0, start = first.date(utc.zone), targetWeekly = 0.0)

        val paces = mutableListOf<Int>()
        for (step in 0..40) {
            val pace = Goal.pace(ledger.dailyBudget(first + step, goal)!! * 7)
            if (pace != paces.lastOrNull()) paces += pace
        }
        assertEquals("one rung at a time, quickening", listOf(4, 3, 1), paces)
    }
}

/**
 * The stepped taper is solved a rung at a time. Walking it a day at a time is the definition, so the walk lives here
 * and the solution must agree with it across every baseline the picker allows and further out than any taper runs.
 */
class SteppedClosedFormTests {
    @Test fun agreesWithTheWalkEveryDay() {
        val utc = DayClock(5, ZoneOffset.UTC)
        val ledger = Ledger(emptyList(), utc)
        val first = DayKey.of(2024, 1, 1)
        val mismatches = mutableListOf<String>()
        var daily = 1.0
        while (daily <= 80) {
            val goal = Goal(isEnabled = true, taper = Taper.DYNAMIC, baselineWeekly = daily * 7, start = first.date(utc.zone), targetWeekly = 0.0)
            var walked = daily
            for (step in 0..900) {
                val solved = ledger.dailyBudget(first + step, goal)!!
                if (abs(solved - walked) > max(1e-9, walked * 1e-9)) mismatches += "$daily u/day, day $step: solved $solved, walked $walked"
                walked *= 1 - Goal.rate(Goal.pace(walked * 7))
            }
            daily += 0.5
        }
        assertTrue("${mismatches.take(5)}", mismatches.isEmpty())
    }
}
