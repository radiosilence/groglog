package cc.blit.groglog

import cc.blit.groglog.core.ReadingKind
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Nights
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.SleepSpan
import cc.blit.groglog.model.SleepStage
import cc.blit.groglog.model.TimeSpan
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.model.isOvernight
import cc.blit.groglog.model.night
import java.time.Instant
import java.time.LocalDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Other apps count standard drinks, not UK units. Getting this wrong raises no error; it silently overstates every
 * reading by three quarters.
 */
class StandardDrinkTests {
    private fun entry(ml: Double, abv: Double): Entry {
        val drink = Drink(name = "Beer", category = DrinkCategory.BEER, abv = abv, vessel = Vessel.PINT, volumeMl = ml)
        return Entry(Pour(drinkId = drink.id, timestamp = Instant.now(), day = 0, vessel = Vessel.PINT, volumeMl = ml, price = 0.0), drink)
    }

    @Test fun oneUnitIsAboutFiveEighthsOfAStandardDrink() {
        // 10 ml of alcohol against 17.7.
        val oneUnit = entry(1000.0, 1.0)
        assertTrue(near(oneUnit.units, 1.0))
        assertTrue(near(oneUnit.standardDrinks, 0.5636, 0.001))
    }

    @Test fun aPintOfFivePercentIsOneAndAHalfStandardDrinks() {
        val pint = entry(568.0, 5.0)
        assertTrue(near(pint.units, 2.84))
        assertTrue(near(pint.standardDrinks, 1.6, 0.01))
    }

    @Test fun unitsAreNeverHandedOverAsDrinks() {
        val pint = entry(568.0, 5.0)
        assertTrue(pint.standardDrinks < pint.units)
    }

    @Test fun nothingDrunkIsNoDrinks() {
        assertEquals(0.0, entry(330.0, 0.0).standardDrinks, 0.0)
    }
}

private val nightClock = DayClock(5, london)

private fun at(day: Int, hour: Int, minute: Int = 0): Instant = LocalDateTime.of(2026, 9, day, hour, minute).atZone(london).toInstant()

/**
 * A reading belongs to the evening that caused it. File one by calendar date and every heavy night's damage lands on
 * the day after, which is usually a quiet one.
 */
class NightTests {
    private val friday = DayKey.of(2026, 9, 18)

    @Test fun theNightAndTheMorningAfterBelongToTheEvening() {
        for (instant in listOf(at(18, 23, 30), at(19, 3), at(19, 7), at(19, 11, 59))) {
            assertEquals(friday, nightClock.night(instant))
        }
        assertEquals(friday - 1, nightClock.night(at(18, 19, 59)))
        assertEquals(friday + 1, nightClock.night(at(19, 20)))
        assertTrue(nightClock.isOvernight(at(19, 3)) && !nightClock.isOvernight(at(19, 15)))
    }

    @Test fun aRestingRateStampedOnTheMorningIsTheNightBefore() {
        // A day's resting rate is stamped across the whole calendar day; its middle is Saturday noon.
        val nights = Nights.of(restingHR = listOf(at(19, 12) to 58.0), clock = nightClock)
        assertEquals(58.0, nights[friday]?.restingHR)
    }

    @Test fun daytimeHRVIsLeftOut() {
        val nights = Nights.of(hrv = listOf(at(19, 2) to 40.0, at(19, 4) to 50.0, at(19, 15) to 90.0), clock = nightClock)
        assertEquals(45.0, nights[friday]?.hrv)
        assertNull(nights[friday - 1])
    }

    @Test fun tooFewNightsIsNoAverage() {
        val nights = Nights.of(hrv = listOf(at(15, 3) to 40.0, at(16, 3) to 50.0), clock = nightClock)
        assertNull(nights.mean(ReadingKind.HRV, (friday - 6)..friday))
        assertEquals(45.0, nights.mean(ReadingKind.HRV, (friday - 6)..friday, minimum = 2))
    }
}

class SleepingHeartRateTests {
    private val tuesday = DayKey.of(2026, 9, 22)

    private fun span(start: Instant, end: Instant, stage: SleepStage = SleepStage.CORE, source: String = "watch") =
        SleepSpan(TimeSpan(start, end), stage, source)

    @Test fun stagesAddUpAndAwakeIsNotSleep() {
        val spans = listOf(
            span(at(23, 0), at(23, 1), SleepStage.DEEP),
            span(at(23, 1), at(23, 1, 30), SleepStage.AWAKE),
            span(at(23, 1, 30), at(23, 3), SleepStage.REM),
            span(at(23, 3), at(23, 7), SleepStage.CORE),
        )
        val sleep = Nights.of(sleep = spans, clock = nightClock)[tuesday]?.sleep!!
        assertEquals(6.5 * 3600, sleep.asleep, 0.0)
        assertEquals(1800.0, sleep.awake, 0.0)
        assertEquals(1.5 / 6.5, sleep.remShare!!, 1e-12)
    }

    @Test fun twoDevicesOnOneNightCountOnce() {
        val spans = listOf(
            span(at(23, 0), at(23, 7), SleepStage.CORE, "garmin"),
            span(at(23, 1), at(23, 5), SleepStage.UNSTAGED, "phone"),
        )
        val sleep = Nights.of(sleep = spans, clock = nightClock)[tuesday]?.sleep!!
        assertEquals(7.0 * 3600, sleep.asleep, 0.0)
        assertEquals(0.0, sleep.unstaged, 0.0)
    }

    @Test fun aLateBedtimeStillBelongsToTheEveningBefore() {
        val asleep = listOf(span(at(23, 4, 36), at(23, 9, 38)))
        val nights = Nights.of(sleep = asleep, heartRate = listOf(at(23, 6) to 60.0, at(23, 7) to 70.0), clock = nightClock)
        assertEquals(65.0, nights[tuesday]?.sleepingHR)
    }

    @Test fun awakeInTheNightAndBeforeSleepAreLeftOut() {
        val asleep = listOf(
            span(at(23, 1), at(23, 3)),
            span(at(23, 3), at(23, 3, 30), SleepStage.AWAKE),
            span(at(23, 3, 30), at(23, 7)),
        )
        val beats = listOf(at(23, 0, 30) to 90.0, at(23, 2) to 60.0, at(23, 3, 15) to 95.0, at(23, 5) to 64.0, at(23, 8) to 88.0)
        assertEquals(62.0, Nights.of(sleep = asleep, heartRate = beats, clock = nightClock)[tuesday]?.sleepingHR)
    }

    @Test fun oneSpanPerNightToFetchWithin() {
        val asleep = listOf(
            span(at(22, 0, 27), at(22, 1, 41)),
            span(at(22, 1, 41), at(22, 1, 49), SleepStage.AWAKE),
            span(at(22, 1, 49), at(22, 9, 22)),
            span(at(23, 4, 36), at(23, 9, 38)),
        )
        val spans = Nights.nightSpans(asleep, nightClock).sortedBy { it.start }
        assertEquals(listOf(TimeSpan(at(22, 0, 27), at(22, 9, 22)), TimeSpan(at(23, 4, 36), at(23, 9, 38))), spans)
    }
}
