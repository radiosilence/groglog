package cc.blit.groglog

import cc.blit.groglog.core.dayCivil
import cc.blit.groglog.core.dayDaysInMonth
import cc.blit.groglog.core.dayDrinking
import cc.blit.groglog.core.dayFormat
import cc.blit.groglog.core.dayIsAfterMidnight
import cc.blit.groglog.core.dayMonthStart
import cc.blit.groglog.core.dayNumber
import cc.blit.groglog.core.dayWeekStart
import cc.blit.groglog.core.dayWeekday
import cc.blit.groglog.core.unitsIsStrength
import cc.blit.groglog.core.unitsKcal
import cc.blit.groglog.core.unitsOf
import cc.blit.groglog.core.unitsStandardDrinkMl
import cc.blit.groglog.core.unitsUnitMl
import cc.blit.groglog.core.unitsWeeklyGuideline
import cc.blit.groglog.export.Exporter
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Seed
import cc.blit.groglog.data.Settings
import cc.blit.groglog.model.Catalog
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.GoalSerializer
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.ServeSize
import cc.blit.groglog.model.Taper
import cc.blit.groglog.model.Units
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.model.leftText
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

class UnitsTests {
    @Test fun pintOfFourPercentIsTwoAndAQuarterUnits() {
        assertTrue(near(Units.of(568.0, 4.0), 2.272, 0.001))
    }

    @Test fun caloriesLandNearDrinkawaresFigures() {
        assertTrue(near(Units.kcal(568.0, 4.0, DrinkCategory.BEER), 182.0, 10.0))
        assertTrue(near(Units.kcal(175.0, 13.0, DrinkCategory.RED_WINE), 159.0, 10.0))
    }

}

/**
 * Per-row arithmetic stays in Kotlin, because each call into the core costs microseconds through JNA. These hold it to
 * the core's, which is the one the iOS app uses.
 */
class CoreParityTests {
    @Test fun constantsMatch() {
        assertEquals(unitsWeeklyGuideline(), Units.WEEKLY_GUIDELINE, 0.0)
        assertEquals(unitsUnitMl(), Units.UNIT_ML, 0.0)
        assertEquals(unitsStandardDrinkMl(), Units.STANDARD_DRINK_ML, 0.0)
    }

    @Test fun dayArithmeticMatches() {
        for (number in -800..80_000 step 7) {
            val key = DayKey(number)
            val core = dayCivil(number.toLong())
            assertEquals(DayKey.Components(core.year.toInt(), core.month.toInt(), core.day.toInt()), key.components)
            assertEquals(number.toLong(), dayNumber(core.year, core.month, core.day))
            assertEquals(DayKey.of(core.year.toInt(), core.month.toInt(), core.day.toInt()), key)
            assertEquals(dayWeekday(number.toLong()).toInt(), key.weekday)
            assertEquals(dayMonthStart(number.toLong()).toInt(), key.monthStart.number)
            assertEquals(dayDaysInMonth(number.toLong()).toInt(), key.daysInMonth)
            assertEquals(dayFormat(number.toLong()), key.toString())
        }
    }

    @Test fun clockRulesMatch() {
        val zone = java.time.ZoneId.of("Europe/London")
        for (rollover in 0..12) for (firstWeekday in 1..2) {
            val clock = DayClock(rollover, zone, firstWeekday)
            for (number in 20_000..20_020) {
                assertEquals(dayWeekStart(number.toLong(), firstWeekday.toLong()).toInt(), clock.weekStart(DayKey(number)).number)
                for (hour in 0..23) {
                    val instant = java.time.LocalDateTime.of(DayKey(number).localDate, java.time.LocalTime.of(hour, 30)).atZone(zone).toInstant()
                    assertEquals(dayDrinking(number.toLong(), hour.toLong(), rollover.toLong()).toInt(), clock.day(instant).number)
                }
            }
            for (hour in 0..23) assertEquals(dayIsAfterMidnight(hour.toLong(), rollover.toLong()), hour < rollover)
        }
    }

    @Test fun unitsMatch() {
        for (ml in listOf(25.0, 125.0, 330.0, 568.0, 750.0)) for (abv in listOf(0.5, 4.0, 5.2, 13.0, 40.0, 100.0)) {
            assertEquals(unitsOf(ml, abv), Units.of(ml, abv), 1e-12)
            assertEquals(unitsKcal(ml, abv, 0.12), Units.kcal(ml, abv, DrinkCategory.STOUT), 1e-9)
        }
        for (abv in listOf(-1.0, 0.0, 0.1, 100.0, 100.1)) assertEquals(unitsIsStrength(abv), Units.isStrength(abv))
    }
}

class ServeSizeTests {
    @Test fun aCatalogueSizeOutsideTheTypesSizesIsOffered() {
        val bottle = ServeSize(Vessel.WINE_BOTTLE, 750.0)
        assertFalse(bottle in DrinkCategory.FORTIFIED.serves)
        val buckfast = Drink(name = "Buckfast", category = DrinkCategory.FORTIFIED, abv = 15.0, vessel = Vessel.WINE_GLASS, volumeMl = 50.0)
        val sizes = buckfast.sizes(ServeSize(Vessel.WINE_GLASS, 50.0))
        assertTrue(bottle in sizes)
        assertTrue(DrinkCategory.FORTIFIED.serves.all { it in sizes })
        assertEquals(sizes.size, sizes.toSet().size)
    }

    @Test fun aDrinkTheCatalogueDoesntKnowKeepsItsTypesSizes() {
        val own = Drink(name = "Home brew", category = DrinkCategory.FORTIFIED, abv = 15.0, vessel = Vessel.WINE_BOTTLE, volumeMl = 750.0)
        assertEquals(DrinkCategory.FORTIFIED.serves, own.sizes(ServeSize(Vessel.WINE_GLASS, 50.0)))
        assertEquals(listOf(ServeSize(Vessel.WINE_BOTTLE, 750.0)) + DrinkCategory.FORTIFIED.serves, own.sizes(ServeSize(Vessel.WINE_BOTTLE, 750.0)))
    }
}

class DayKeyTests {
    @Test fun roundTripsThroughCivilDates() {
        assertEquals(0, DayKey.of(1970, 1, 1).number)
        for (number in -800_000..800_000 step 997) {
            val c = DayKey(number).components
            assertEquals(number, DayKey.of(c.year, c.month, c.day).number)
        }
        assertEquals("2026-09-19", DayKey.parse("2026-09-19").toString())
    }

    @Test fun refusesDatesThatDoNotExist() {
        assertEquals("2026-09-03", DayKey.parse("2026-9-3").toString())
        assertNotNull(DayKey.parse("2024-02-29"))
        for (bad in listOf("2026-13-01", "2026-06-31", "2025-02-29", "30-09-2026", "0001-01-01", "999999999999999999-01-01", "2026-09")) {
            assertNull(bad, DayKey.parse(bad))
        }
    }

    @Test fun knowsWeekdaysAndMonths() {
        assertEquals(7, DayKey.of(2026, 9, 19).weekday)
        assertEquals(29, DayKey.of(2024, 2, 10).daysInMonth)
        assertEquals(28, DayKey.of(2026, 2, 10).daysInMonth)
        assertEquals(DayKey.of(2026, 9, 1), DayKey.of(2026, 9, 19).monthStart)
    }
}

class DayClockTests {
    @Test fun smallHoursBelongToTheNightBefore() {
        assertEquals(DayKey.of(2026, 9, 19), clock.day(date(2026, 9, 20, 1, 30)))
        assertEquals(DayKey.of(2026, 9, 20), clock.day(date(2026, 9, 20, 5, 0)))
    }

    @Test fun theRolloverHoldsOnTheNightsTheClocksChange() {
        // Back an hour on 25 October, forward on 29 March: 04:30 is still last night, 05:30 is already today.
        assertEquals(DayKey.of(2026, 10, 24), clock.day(date(2026, 10, 25, 4, 30)))
        assertEquals(DayKey.of(2026, 3, 29), clock.day(date(2026, 3, 29, 5, 30)))
        for (day in listOf(DayKey.of(2026, 10, 25), DayKey.of(2026, 3, 29))) {
            assertEquals(day, clock.day(clock.start(day)))
            assertEquals(day - 1, clock.day(clock.start(day).minusSeconds(60)))
        }
    }

    @Test fun resolvingATimeLandsWithinTheDrinkingDay() {
        val day = DayKey.of(2026, 9, 19)
        assertEquals(date(2026, 9, 20, 1, 30), clock.resolve(date(2000, 1, 1, 1, 30), day))
        assertEquals(date(2026, 9, 19, 21, 0), clock.resolve(date(2000, 1, 1, 21, 0), day))
    }

    @Test fun weeksStartOnTheCalendarsFirstWeekday() {
        assertEquals(DayKey.of(2026, 9, 14), clock.weekStart(DayKey.of(2026, 9, 19)))
    }
}

@RunWith(RobolectricTestRunner::class)
class LogbookTests {
    @Test fun keepsDayTotalsInStepWithEntries() = runBlocking {
        val (logbook, drink) = logbook()
        val night = date(2026, 9, 19, 21)
        logbook.log(Serve(drink), listOf(night, night.plusSeconds(1800), date(2026, 9, 20, 1)))
        val saturday = DayKey.of(2026, 9, 19)
        assertEquals(3, ledger(logbook).totals(saturday).count)

        val pours = entries(logbook, saturday..saturday).map { it.pour }
        logbook.delete(pours[0])
        logbook.update(pours[1], date(2026, 9, 20, 20), Vessel.HALF, 284.0, 3.0)
        val after = ledger(logbook)
        assertEquals(1, after.totals(saturday).count)
        assertTrue(near(after.totals(saturday + 1).units, Units.of(284.0, 5.0)))

        logbook.save(drink.copy(abv = 4.0))
        assertTrue(near(ledger(logbook).totals(saturday).units, Units.of(568.0, 4.0)))
    }

    @Test fun dryMarksGiveWayToDrinksAndEmptyDaysDisappear() = runBlocking {
        val (logbook, drink) = logbook()
        val day = DayKey.of(2026, 9, 10)
        logbook.setAlcoholFree(true, day)
        assertEquals(DayStatus.ALCOHOL_FREE, ledger(logbook).status(day))
        logbook.log(Serve(drink), listOf(date(2026, 9, 10, 20)))
        assertEquals(DayStatus.DRANK, ledger(logbook).status(day))
        entries(logbook, day..day).forEach { logbook.delete(it.pour) }
        assertEquals(0, logbook.rows.dayCount())
    }

    /**
     * A guest ale logged as Beer at the pump clip's strength counts at that strength, and leaves Beer and its other
     * entries as they were. Logging at the drink's own strength stores no override.
     */
    @Test fun aRoundLoggedAtItsOwnStrengthLeavesTheDrinkAlone() = runBlocking {
        val (logbook, drink) = logbook()
        val day = DayKey.of(2026, 9, 19)
        logbook.log(Serve(drink), listOf(date(2026, 9, 19, 20)), abv = 5.0)
        logbook.log(Serve(drink), listOf(date(2026, 9, 19, 21)), abv = 6.5)
        val logged = entries(logbook, day..day).sortedBy { it.timestamp }
        assertEquals(listOf(null, 6.5), logged.map { it.pour.abvOverride })
        assertEquals(listOf(5.0, 6.5), logged.map { it.abv })
        assertTrue(near(ledger(logbook).totals(day).units, Units.of(568.0, 5.0) + Units.of(568.0, 6.5), 0.001))
        assertEquals(5.0, logbook.rows.drink(drink.id)?.abv)

        val guest = logged[1].pour
        logbook.update(guest, guest.timestamp, Vessel.PINT, 568.0, guest.price, abvOverride = 5.8)
        assertEquals(5.8, entries(logbook, day..day).first { it.id == guest.id }.abv, 0.0)
        logbook.update(guest, guest.timestamp, Vessel.PINT, 568.0, guest.price)
        assertTrue(entries(logbook, day..day).all { it.abv == 5.0 })
        assertTrue(!Units.isStrength(0.0) && !Units.isStrength(101.0) && Units.isStrength(5.2))
    }

    /** Undo takes the drink logged last, not the one drunk last: one backdated is the one you meant to take back. */
    @Test fun undoTakesTheLastLoggedNotTheLastDrunk() = runBlocking {
        val (logbook, drink) = logbook()
        val day = DayKey.of(2026, 9, 19)
        logbook.log(Serve(drink), listOf(date(2026, 9, 19, 22)))
        logbook.log(Serve(drink, Vessel.HALF, 284.0), listOf(date(2026, 9, 19, 20)))
        logbook.undo(day)
        val left = entries(logbook, day..day)
        assertTrue(left.size == 1 && left[0].vessel == Vessel.PINT)
        assertEquals(1, ledger(logbook).totals(day).count)
        logbook.undo(day)
        logbook.undo(day)
        assertNotEquals(DayStatus.DRANK, ledger(logbook).status(day))
    }

    /** A week with nights missing is a week of unknowns, not a light one. */
    @Test fun theWeeklyAverageLeavesOutDaysNobodyLogged() = runBlocking {
        val (logbook, drink) = logbook()
        val monday = DayKey.of(2026, 9, 14)
        logbook.log(Serve(drink), listOf(date(2026, 9, 14, 20), date(2026, 9, 15, 20)))
        logbook.setAlcoholFree(true, monday + 2)
        val average = ledger(logbook).weeklyAverage(monday..(monday + 6))!!
        assertTrue("two pints over three logged days, at seven days a week", near(average, Units.of(568.0, 5.0) * 2 / 3 * 7))
        assertNull(ledger(logbook).weeklyAverage((monday - 7)..(monday - 1)))
    }

    @Test fun handSetSpendStandsUntilCleared() = runBlocking {
        val (logbook, drink) = logbook()
        val day = DayKey.of(2026, 9, 19)
        logbook.log(Serve(drink), listOf(date(2026, 9, 19, 20), date(2026, 9, 19, 22)))
        assertEquals(10.0, ledger(logbook).totals(day).cost, 0.0)

        logbook.setSpend(42.0, day)
        assertEquals(42.0, ledger(logbook).totals(day).cost, 0.0)
        assertEquals(10.0, ledger(logbook).derivedSpend(day), 0.0)

        // Another round, and a rebuild, leave it standing.
        logbook.log(Serve(drink), listOf(date(2026, 9, 19, 23)))
        logbook.rebuild()
        assertEquals(42.0, ledger(logbook).totals(day).cost, 0.0)
        assertEquals(15.0, ledger(logbook).derivedSpend(day), 0.0)

        logbook.setSpend(null, day)
        assertNull(ledger(logbook).spendOverride(day))
        assertEquals(15.0, ledger(logbook).totals(day).cost, 0.0)
    }

    @Test fun aSpendOnItsOwnIsntADrinkingDay() = runBlocking {
        val (logbook, _) = logbook()
        val day = DayKey.of(2026, 9, 1)
        logbook.setSpend(20.0, day)
        val after = ledger(logbook)
        assertEquals(20.0, after.totals(day).cost, 0.0)
        assertFalse(after.isLogged(day))
        logbook.setSpend(null, day)
        assertEquals(0, logbook.rows.dayCount())
    }

    @Test fun rebuildAgreesWithIncrementalUpdates() = runBlocking {
        val (logbook, drink) = logbook()
        for (offset in 0 until 20) {
            logbook.log(Serve(drink), listOf(date(2026, 8, 1 + offset, 20), date(2026, 8, 1 + offset, 22)))
        }
        logbook.setAlcoholFree(true, DayKey.of(2026, 8, 25))
        val incremental = logbook.rows.days().sortedBy { it.number }
        logbook.rebuild()
        assertEquals(incremental, logbook.rows.days().sortedBy { it.number })
    }

    @Test fun loggedDrinksHaveNoDeleteButCanBeHidden() = runBlocking {
        val (logbook, drink) = logbook()
        logbook.log(Serve(drink), listOf(Instant.now()))
        assertThrows(Exception::class.java) { runBlocking { logbook.rows.delete(drink) } }
        logbook.delete(drink)
        assertNotNull(logbook.rows.drink(drink.id))
    }
}

class TaperTests {
    private val empty = Ledger(emptyList(), clock)
    private val weekly = Goal(isEnabled = true, taper = Taper.PROPORTIONAL, baselineWeekly = 70.0, reductionPercent = 10.0, periodDays = 7, start = date(2026, 9, 1), targetWeekly = 14.0)

    @Test fun scheduleCompoundsSmoothlyPerPeriod() {
        val start = DayKey.of(2026, 9, 1)
        assertEquals(10.0, empty.dailyBudget(start, weekly)!!, 0.0)
        assertTrue(near(empty.dailyBudget(start + 7, weekly)!!, 9.0))
        val midWeek = empty.dailyBudget(start + 3, weekly)!!
        assertTrue(midWeek < 10 && midWeek > 9)
        assertEquals(2.0, empty.dailyBudget(start + 800, weekly)!!, 0.0)
        assertNull(empty.dailyBudget(start - 1, weekly))
    }

    @Test fun tenPercentADayIsExactlyTheSafeLimit() {
        val daily = weekly.copy(periodDays = 1)
        assertFalse(daily.isFasterThanSafe)
        assertTrue(daily.copy(reductionPercent = 25.0).isFasterThanSafe)
    }

    @Test fun projectsTargetAndStopDates() {
        // Started today by the drinking-day clock: before 5am now is still yesterday's drinking day.
        val goal = weekly.copy(start = clock.start(empty.today))
        val projection = empty.projection(goal)
        assertTrue(empty.today.distanceTo(projection.target!!) in 105..109)
        // It starts at ten a day, which is already low enough to stop from, so the stop date is today rather than
        // months out at the tail of the curve.
        assertEquals(empty.today, projection.stoppable!!)
    }
}

/**
 * Offering the same cuts for every period would let "−50%" and "day" together mean halving drinking daily, well past
 * the rate the same screen warns is a withdrawal risk.
 */
class TaperOfferTests {
    /**
     * The share is fixed at the fastest safe rate, so it stays within the limit however often it applies. A menu of
     * shares could not promise that: −50% is safe once a week and −20% once every three days.
     */
    @Test fun nothingYouCanPickIsFasterThanIsSafe() {
        for (period in Goal.periods) {
            val goal = Goal(isEnabled = true, periodDays = period.days)
            assertFalse("${Goal.STANDARD_CUT.toInt()}% every ${period.label} is ${goal.dailyCut} a day", goal.isFasterThanSafe)
        }
    }

    @Test fun thePeriodIsTheWholeOfThePace() {
        val paces = Goal.periods.map { Goal(periodDays = it.days).dailyCut }
        assertEquals("a day apart is the fastest, a week apart the gentlest", paces.sortedDescending(), paces)
        Goal.pace(20 * 7.0)
        assertTrue(near(paces.first(), 0.10))
        assertTrue(paces.last() < 0.02)
    }

    @Test fun theDefaultIsTenPercentEveryFourDaysToNothing() {
        val goal = Goal()
        assertTrue(goal.reductionPercent == 10.0 && goal.periodDays == 4)
        assertEquals(0.0, goal.targetWeekly, 0.0)
        // The rate to start somebody on, slower than the fastest safe one.
        assertTrue(near(goal.dailyCut, 0.026, 0.001))
        assertFalse(goal.isFasterThanSafe)
        val projection = Ledger(emptyList(), clock).projection(Goal(isEnabled = true, taper = Taper.PROPORTIONAL, baselineWeekly = 70.0, start = clock.start(clock.today)))
        assertNull("a share never reaches nothing", projection.target)
        assertNotNull("and it always reaches a level it can be stopped from", projection.stoppable)
    }

    /** A goal saved when the picker offered other periods keeps its pace, not its number of days. */
    @Test fun aRetiredPeriodMovesToWhicheverKeepsThePace() {
        // -50% a week was 9.4% a day, which is nearest to 10% every day.
        val moved = GoalSerializer.decode("""{"isEnabled":true,"reductionPercent":50,"periodDays":7}""")
        assertEquals(Goal.STANDARD_CUT, moved.reductionPercent, 0.0)
        assertEquals("9.4% a day belongs next to 10% a day, not next to a week", 1, moved.periodDays)
        // -10% every twelve weeks was 0.1% a day, which is nearest to the gentlest still offered.
        assertEquals(7, GoalSerializer.decode("""{"isEnabled":true,"reductionPercent":10,"periodDays":84}""").periodDays)
    }

    /**
     * The numbers the screen leans on, tied to where they come from. DHSC's UK clinical guidelines for alcohol treatment
     * (ch. 8, Nov 2025) for the pace; NICE CG115 recs 1.3.4.1 and 1.3.4.5 for when to refer to a clinician instead of
     * offering a slower plan.
     */
    @Test fun theLimitsAreTheOnesTheGuidanceGives() {
        assertEquals("DHSC: no more than 10% a day", 0.10, Goal.SAFE_DAILY_CUT, 0.0)
        assertEquals("DHSC: over 25 a day, consider 10% every four days", 25.0, Goal.SLOWER_ABOVE_WEEKLY / 7, 0.0)
        assertEquals("NICE CG115 1.3.4.1", 15.0, Goal.ASSISTED_WITHDRAWAL_WEEKLY / 7, 0.0)
        assertEquals("NICE CG115 1.3.4.5", 30.0, Goal.INPATIENT_WEEKLY / 7, 0.0)
        // The default is what DHSC suggests for the people this app mostly serves.
        assertTrue(Goal().periodDays == 4 && Goal().reductionPercent == 10.0)
    }

    /**
     * A share is self-limiting: ten per cent of whatever is being drunk cannot breach the ceiling in any period. A fixed
     * number of units can, near the bottom of the taper.
     */
    @Test fun nothingOfferedStartsSteeperThanTheCeiling() {
        var daily = 4.0
        while (daily <= 80) {
            val weekly = daily * 7
            for (period in Goal.periods(weekly)) {
                assertFalse(Goal(periodDays = period.days).isFasterThanSafe)
                for (units in Goal.unitCuts(weekly, period.days)) {
                    val opening = units / period.days / daily
                    // The smallest cut always stands, even where a tenth of the drinking is less than it.
                    if (units <= Goal.unitCuts.min() || weekly < Goal.ASSISTED_WITHDRAWAL_WEEKLY) continue
                    assertTrue("−$units u every ${period.label} on $daily u/day opens at $opening", opening <= Goal.SAFE_DAILY_CUT + 0.0001)
                }
            }
            daily += 2
        }
    }

    @Test fun aFastTaperIsWithheldFromWhoeverIsDrinkingMost() {
        // DHSC names 25 a day as the point to go slower, and says every four days rather than every day.
        assertEquals(listOf(1, 3, 4, 7), Goal.periods(14 * 7.0).map { it.days })
        assertEquals("ours, on NICE's line at 15", listOf(3, 4, 7), Goal.periods(20 * 7.0).map { it.days })
        assertEquals(listOf(4, 7), Goal.periods(40 * 7.0).map { it.days })
    }

    /**
     * Ten per cent is the only rate the guidance gives, so it is the only one enforced. A share is self-limiting and a
     * fixed number of units is not, so only the linear amounts are filtered.
     */
    @Test fun noLinearAmountOpensSteeperThanTenPerCent() {
        var daily = 4.0
        while (daily <= 80) {
            for (period in Goal.periods(daily * 7)) {
                for (units in Goal.unitCuts(daily * 7, period.days)) {
                    if (units <= Goal.unitCuts[0]) continue
                    val opening = units / period.days / daily
                    assertTrue("−$units u every ${period.label} on $daily u/day opens at $opening", opening <= Goal.SAFE_DAILY_CUT + 0.0001)
                }
            }
            daily += 1
        }
    }

    /**
     * Dynamic is a plan and does not read the log: the pace follows where the budget has got to, so it quickens a rung
     * at a time on the way down and nothing drunk moves it.
     */
    @Test fun dynamicQuickensAsTheBudgetFalls() {
        val goal = Goal(isEnabled = true, taper = Taper.DYNAMIC, baselineWeekly = 40 * 7.0, start = date(2026, 9, 1))
        val ledger = Ledger(emptyList(), clock)
        val start = DayKey.of(2026, 9, 1)
        val day = { n: Int -> ledger.dailyBudget(start + n, goal)!! }
        // It opens on the rung the guidance names for over 25 a day.
        val first = day(0) - day(1)
        assertTrue(near(first / 40, Goal.rate(4)))
        // And by the time the budget is under fifteen it's on the quickest.
        val at60 = day(60)
        val late = at60 - day(61)
        assertTrue(near(late / at60, Goal.rate(1)))
        // Falling all the way, and never faster than the ceiling.
        assertTrue(day(60) < day(30) && day(30) < day(0))
        val steps = (0 until 90).map { (day(it) - day(it + 1)) / day(it) }
        assertTrue(steps.all { it <= Goal.SAFE_DAILY_CUT + 0.0001 })
        assertTrue("gentle at the top, quick at the bottom", steps.first() < steps.last())
    }

    /**
     * The ladder and the picker are the same list, so the automatic pace can never be gentler than the quickest you
     * could have picked by hand at that level.
     */
    @Test fun theLadderIsWhateverThePickerWouldOffer() {
        var daily = 4.0
        while (daily <= 80) {
            assertEquals("at $daily u/day", Goal.periods(daily * 7).minOf { it.days }, Goal.pace(daily * 7))
            daily += 1
        }
        assertEquals("the DHSC limit over 25 a day", 4, Goal.pace(40 * 7.0))
        assertEquals("ours, on NICE's line at 15", 3, Goal.pace(20 * 7.0))
        assertEquals("the ceiling, under it", 1, Goal.pace(14 * 7.0))
    }

    /** A stepped taper's own period is never used, so anything that names its pace has to ask the ladder. */
    @Test fun aSteppedTapersPaceIsTheRungItHasReached() {
        val goal = Goal(isEnabled = true, taper = Taper.DYNAMIC, baselineWeekly = 40 * 7.0, periodDays = 7, start = date(2026, 9, 1))
        val ledger = Ledger(emptyList(), clock)
        val start = DayKey.of(2026, 9, 1)
        assertEquals("before it starts, its baseline's rung", 4, ledger.pace(start - 5, goal))
        assertEquals(4, ledger.pace(start, goal))
        assertEquals(1, ledger.pace(start + 90, goal))
        assertEquals("any other taper is the period it was given", 7, ledger.pace(start + 90, goal.copy(taper = Taper.PROPORTIONAL)))
    }

    /** Nothing logged changes the budget. */
    @Test fun dynamicIgnoresWhatIsActuallyDrunk() {
        val goal = Goal(isEnabled = true, taper = Taper.DYNAMIC, baselineWeekly = 30 * 7.0, start = date(2026, 9, 1))
        val start = DayKey.of(2026, 9, 1)
        val quiet = (0 until 7).map { Day((start + it).number, isAlcoholFree = true) }
        val withoutLog = Ledger(emptyList(), clock).dailyBudget(start + 10, goal)!!
        val withLog = Ledger(quiet, clock).dailyBudget(start + 10, goal)!!
        assertEquals(withoutLog, withLog, 0.0)
    }

    /**
     * Raising a taper's starting point can remove its pace from the offered list. It then steps to the quickest pace
     * still offered rather than to the gentlest.
     */
    @Test fun raisingTheStartMovesToTheNextPaceStillOffered() {
        // Every day is offered at 14 a day. At 20 it is not, and three days is the next one along.
        assertEquals(1, Goal.nearestOffered(1, 14 * 7.0))
        assertEquals(3, Goal.nearestOffered(1, 20 * 7.0))
        // Past 25 the guidance removes the quicker two, so four days is what remains.
        assertEquals(4, Goal.nearestOffered(1, 30 * 7.0))
        assertEquals(4, Goal.nearestOffered(3, 30 * 7.0))
        // A pace that's still offered is left where it is.
        assertEquals(4, Goal.nearestOffered(4, 80 * 7.0))
    }

    @Test fun raisingTheStartKeepsALinearCutIfItCan() {
        // Two a day is safe from forty. From eighteen it is over a tenth, so it drops to one and a half.
        assertEquals(2.0, Goal.nearestOffered(2.0, 40 * 7.0, 1), 0.0)
        assertEquals(1.5, Goal.nearestOffered(2.0, 18 * 7.0, 1), 0.0)
        // At ten a day it is a fifth, so it drops again.
        assertEquals(1.0, Goal.nearestOffered(2.0, 10 * 7.0, 1), 0.0)
        // Spread over four days the same two units is gentle again.
        assertEquals(2.0, Goal.nearestOffered(2.0, 18 * 7.0, 4), 0.0)
    }

    @Test fun theOpeningStepIsWhatThePercentageHides() {
        assertTrue("a tenth of sixty", near(Goal(taper = Taper.PROPORTIONAL, periodDays = 1).openingDrop(60 * 7.0), 6.0))
        // Dynamic's is whatever rung sixty a day puts it on, which is the gentlest.
        assertTrue(near(Goal(taper = Taper.DYNAMIC).openingDrop(60 * 7.0), 60 * Goal.rate(4)))
        assertTrue(near(Goal(taper = Taper.LINEAR, reductionUnits = 2.0, periodDays = 4).openingDrop(60 * 7.0), 0.5))
    }

    /** Ten per cent of whatever the taper starts from, wherever that is. */
    @Test fun aLinearCutIsWithheldWhereverItWouldOpenTooSteep() {
        // Two a day off twenty a day is a tenth of it, right on the ceiling; off eighteen it's over.
        assertEquals(listOf(0.5, 1.0, 1.5), Goal.unitCuts(18 * 7.0, 1))
        assertEquals(Goal.unitCuts, Goal.unitCuts(40 * 7.0, 1))
        // Ten a day would be a fifth gone by morning, so only a tenth of it stands.
        assertEquals(listOf(0.5, 1.0), Goal.unitCuts(10 * 7.0, 1))
        assertEquals(listOf(0.5, 1.0, 1.5), Goal.unitCuts(15 * 7.0, 1))
        // However little is being drunk, the smallest stands rather than leaving nothing.
        assertEquals(listOf(0.5), Goal.unitCuts(2 * 7.0, 1))
        // Spread over four days the same two units is gentle again, so it comes back either way.
        assertEquals(Goal.unitCuts, Goal.unitCuts(18 * 7.0, 4))
    }

    @Test fun aLinearCutStopsAtTwoUnits() {
        assertEquals(2.0, Goal.unitCuts.max(), 0.0)
        assertTrue(0.5 in Goal.unitCuts && 1.0 in Goal.unitCuts)
        assertEquals("the model holds what it's given", 5.0, Goal(taper = Taper.LINEAR, reductionUnits = 5.0).reductionUnits, 0.0)
    }
}

@RunWith(RobolectricTestRunner::class)
class ExportedTaperTests {
    @Test fun theExportDescribesTheSteppedTaperItRuns() = runBlocking {
        val settings = Settings(goal = Goal(isEnabled = true, taper = Taper.DYNAMIC))
        val (logbook, _) = logbook()
        val text = Exporter.markdown(Exporter.backup(logbook.database, settings))
        assertTrue(text.contains("stepped taper") && text.contains("fixed schedule"))
        assertFalse("it reads nothing of what's drunk", text.contains("average"))
    }
}

/**
 * A linear taper takes the same units off every day rather than the same share, so unlike a proportional one it reaches
 * nothing, and takes a bigger share the lower it gets.
 */
class LinearTaperTests {
    private val start = DayKey.of(2026, 9, 1)
    private val goal = Goal(isEnabled = true, taper = Taper.LINEAR, baselineWeekly = 70.0, reductionUnits = 1.0, periodDays = 7, start = date(2026, 9, 1), targetWeekly = 0.0)

    @Test fun comesDownByTheSameAmountEveryDay() {
        val ledger = Ledger(emptyList(), clock)
        // 70 a week is 10 a day; 1 u/day off per week is a seventh of a unit a day.
        val day = { n: Int -> ledger.dailyBudget(start + n, goal)!! }
        assertTrue(near(day(0), 10.0))
        assertTrue(near(day(7), 9.0))
        assertTrue(near(day(70), 0.0))
        val steps = (0 until 30).map { day(it + 1) - day(it) }
        assertTrue("${steps.take(5)}", steps.all { near(it, steps[0]) })
    }

    @Test fun landsOnNothingAndStaysThere() {
        assertEquals(0.0, Ledger(emptyList(), clock).dailyBudget(start + 140, goal)!!, 0.0)
    }

    /** The proportional taper only approaches nought; the linear one reaches it. */
    @Test fun hasAdateForNothingWhereProportionalNeverDoes() {
        val today = clock.today
        val landing = Goal(isEnabled = true, taper = Taper.LINEAR, baselineWeekly = 70.0, reductionUnits = 1.0, periodDays = 7, start = clock.start(today), targetWeekly = 0.0)
        val easing = Goal(isEnabled = true, taper = Taper.PROPORTIONAL, baselineWeekly = 70.0, periodDays = 7, start = clock.start(today), targetWeekly = 0.0)
        val ledger = Ledger(emptyList(), clock)
        assertNotNull(ledger.projection(landing).target)
        assertNull(ledger.projection(easing).target)
    }

    /** Its share of what's left climbs as the budget falls, which is the risk a proportional taper doesn't carry. */
    @Test fun saysWhereItStartsCuttingFasterThanIsSafe() {
        // A seventh of a unit a day is 10% of 1.43 u/day, and sharper than that below it.
        assertTrue(near(goal.sharpensBelow, (1.0 / 7) / Goal.SAFE_DAILY_CUT))
        assertFalse(goal.isFasterThanSafe)
    }

    /**
     * The 10%-a-day limit is about withdrawal, which is not a risk near the guideline. Saying a taper turns sharp below
     * 1.4 u/day would warn about the level the same screen recommends.
     */
    @Test fun saysNothingWhereTheGuidelineWouldContradictIt() {
        assertTrue(goal.sharpensBelow < Units.WEEKLY_GUIDELINE / 7)
        assertFalse(goal.sharpensWhileItMatters(40 * 7.0))
        // A unit a day off every day sharpens from ten a day down, which is worth knowing about.
        val brisk = goal.copy(periodDays = 1)
        assertEquals(10.0, brisk.sharpensBelow, 0.0)
        assertTrue(brisk.sharpensWhileItMatters(40 * 7.0))
        assertFalse("nothing to warn about at ten a day", brisk.sharpensWhileItMatters(10 * 7.0))
        // Nothing to say about a taper that isn't linear, whatever its numbers.
        assertFalse(brisk.copy(taper = Taper.PROPORTIONAL).sharpensWhileItMatters(40 * 7.0))
    }
}

@RunWith(RobolectricTestRunner::class)
class ExportTests {
    @Test fun theExportIsWorthSharing() = runBlocking {
        val (logbook, drink) = logbook()
        logbook.log(Serve(drink), listOf(Instant.now()))
        val text = Exporter.markdown(Exporter.backup(logbook.database, Settings()))
        assertTrue("the iOS bug shipped 170 bytes of file path instead of this", text.length > 170)
        assertTrue(text.contains(drink.name))
    }
}

/**
 * `Prefs` reads the goal leniently and falls back to a fresh one, so a goal that won't decode is a goal silently thrown
 * away. Every field has to be optional on the way in.
 */
class GoalDecodingTests {
    @Test fun aGoalSavedBeforeAFieldExistedKeepsWhatItDidSet() {
        val goal = GoalSerializer.decode("""{"isEnabled":true,"isDynamic":false,"baselineWeekly":70,"reductionPercent":25,"periodDays":7,"targetWeekly":14}""")
        assertTrue(goal.isEnabled && goal.baselineWeekly == 70.0 && goal.targetWeekly == 14.0)
        assertEquals("isDynamic:false was the proportional taper", Taper.PROPORTIONAL, goal.taper)
        assertEquals("a field it never knew about takes the default", Goal().reductionUnits, goal.reductionUnits, 0.0)
        // 25% a week was 4% a day, and the nearest pace still offered is 10% every three days.
        assertTrue(goal.reductionPercent == Goal.STANDARD_CUT && goal.periodDays == 3)
        assertTrue("and it's still going at roughly the pace it was", near(goal.dailyCut, 0.0345, 0.001))
    }

    @Test fun theOldDynamicFlagBecomesTheDynamicTaper() {
        assertEquals(Taper.DYNAMIC, GoalSerializer.decode("""{"isEnabled":true,"isDynamic":true}""").taper)
    }

    @Test fun aGoalSurvivesTheRoundTrip() {
        // Dates travel as whole seconds, as iOS writes them.
        val goal = Goal(isEnabled = true, taper = Taper.LINEAR, baselineWeekly = 63.0, reductionUnits = 2.0, periodDays = 7, start = Instant.ofEpochSecond(1_790_000_000))
        assertEquals(goal, GoalSerializer.decode(GoalSerializer.encode(goal).toString()))
    }
}

/**
 * A budget taken from a rolling average of what was drunk would vanish across a gap in the log, and a quiet day could
 * take three quarters off it. Dynamic is a plan that reads nothing from the log.
 */
@RunWith(RobolectricTestRunner::class)
class DynamicBudgetTests {
    @Test fun aGapInTheLogNoLongerLeavesYouWithoutABudget() = runBlocking {
        val (logbook, _) = logbook()
        val goal = Goal(isEnabled = true, taper = Taper.DYNAMIC, baselineWeekly = 70.0, start = clock.start(clock.today))
        assertNotNull(ledger(logbook).dailyBudget(clock.today, goal))
    }
}

class CurveTests {
    @Test fun cumulativeStepsUpAtEachDrink() {
        val day = DayKey.of(2026, 9, 19)
        val drink = beer()
        val entries = listOf(date(2026, 9, 19, 20), date(2026, 9, 20, 1)).map {
            Entry(Pour(drinkId = drink.id, timestamp = it, day = day.number, vessel = Vessel.PINT, volumeMl = 568.0, price = 5.0), drink)
        }
        val points = Ledger(emptyList(), clock).cumulative(entries, day)
        assertEquals(listOf(0.0, 15.0, 20.0, 24.0), points.map { it.x })
        assertTrue(near(points.last().units, 2 * Units.of(568.0, 5.0), 0.001))
    }

    /**
     * The week line is rolled flat over three hours, which must not cost it the two things that make it a running
     * total: it only ever rises, and it ends on the week's mean.
     */
    @Test fun theWeekAverageIsSmoothedButStillARunningTotal() {
        val day = DayKey.of(2026, 9, 20)
        val week = (day - 7)..(day - 1)
        val drink = beer()
        // A pint on two of the seven days, hours apart, so an unsmoothed mean would step twice. The other five are
        // alcohol-free, so all seven count and the mean lands on two pints across seven days.
        val drinking = listOf(DayKey.of(2026, 9, 14), DayKey.of(2026, 9, 18))
        val entries = drinking.zip(listOf(date(2026, 9, 14, 19), date(2026, 9, 18, 22))) { on, at ->
            Entry(Pour(drinkId = drink.id, timestamp = at, day = on.number, vessel = Vessel.PINT, volumeMl = 568.0, price = 5.0), drink)
        }
        val wet = drinking.map { it.number }.toSet()
        val rows = week.map { Day(it.number, isAlcoholFree = it.number !in wet, count = if (it.number in wet) 1 else 0) }
        val points = Ledger(rows, clock).averageCumulative(entries, week)
        assertTrue(points.isNotEmpty())
        assertTrue(points.zipWithNext().all { (a, b) -> a.units <= b.units + 0.0001 })
        assertTrue(near(points.last().units, 2 * Units.of(568.0, 5.0) / 7, 0.001))
        assertEquals(0.0, points.first().units, 0.0)
    }
}

@RunWith(RobolectricTestRunner::class)
class ReferenceTests {
    @Test fun entriesFollowTheirDrinkButKeepTheirSizeAndPrice() = runBlocking {
        val (logbook, drink) = logbook(Drink(name = "Staropramen", category = DrinkCategory.BEER, abv = 5.0, vessel = Vessel.CAN, volumeMl = 440.0, price = 2.0))
        logbook.log(Serve(drink), listOf(Instant.now()))
        logbook.log(Serve(drink, Vessel.PINT, 568.0), listOf(Instant.now()))
        logbook.save(drink.copy(name = "Staropramen Premium", abv = 4.0, price = 3.0))
        val today = clock.day(Instant.now())
        val logged = entries(logbook, today..today)
        assertTrue(logged.all { it.name == "Staropramen Premium" && it.abv == 4.0 })
        assertEquals(listOf(Vessel.CAN, Vessel.PINT), logged.map { it.vessel })
        assertEquals(2.0, logged[0].price, 0.0)
        // The can was priced by hand at £2 and keeps it. The pint was never priced by hand, so it took the catalogue's
        // pint price rather than £2 stretched to a pint's worth of volume.
        assertTrue(near(logged[1].price, Catalog.price("Staropramen", DrinkCategory.BEER, Vessel.PINT, 568.0)!!))
    }
}

@RunWith(RobolectricTestRunner::class)
class BackupTests {
    @Test fun roundTripsAndIsIdempotent() = runBlocking {
        val prefs = prefs()
        val settings = prefs.current()
        val logbook = Logbook(database(), settings.clock)
        val drink = Drink(name = "Hepcat", category = DrinkCategory.BEER, abv = 4.6, vessel = Vessel.PINT, volumeMl = 568.0)
        logbook.add(drink)
        logbook.pin(Serve(drink, Vessel.CAN, 440.0, 3.0))
        logbook.log(Serve(drink), listOf(Instant.now().minusSeconds(3600 * 30)), abv = 5.2)
        logbook.setAlcoholFree(true, settings.clock.today - 3)
        val data = Exporter.json(Exporter.backup(logbook.database, settings))

        val target = database()
        assertEquals(1, Exporter.restore(data, target, prefs))
        assertEquals(0, Exporter.restore(data, target, prefs))
        val rows = target.rows()
        assertEquals(1, rows.pourCount())
        assertEquals(5.2, rows.pours().single().abvOverride!!, 0.0)
        val days = rows.days()
        assertTrue(days.size == 2 && days.count { it.isAlcoholFree } == 1)
        assertEquals(2, rows.favouriteCount())
        assertEquals(3.0, rows.favourites().single { it.vessel == Vessel.CAN }.price, 0.0)
    }

    @Test fun restoringOntoAFreshInstallDoesntDoubleDrinks() = runBlocking {
        val prefs = prefs()
        val settings = prefs.current()
        val logbook = Logbook(database(), settings.clock)
        Seed.drinksIfNeeded(logbook)
        val beer = logbook.rows.drink("Beer", DrinkCategory.BEER.raw)!!
        logbook.log(Serve(beer), listOf(Instant.now()))
        val data = Exporter.json(Exporter.backup(logbook.database, settings))
        val drinks = logbook.rows.drinkCount()
        val favourites = logbook.rows.favouriteCount()

        val fresh = database()
        Seed.drinksIfNeeded(Logbook(fresh, settings.clock))
        Exporter.restore(data, fresh, prefs)
        val rows = fresh.rows()
        assertEquals(drinks, rows.drinkCount())
        assertEquals(favourites, rows.favouriteCount())
        assertEquals(1, rows.entries().size)
    }

    @Test fun importingADryDayKeepsASpendSetByHand() = runBlocking {
        val prefs = prefs()
        val database = database()
        val day = DayKey.of(2026, 9, 11)
        Logbook(database, prefs.current().clock).setSpend(12.0, day)
        Exporter.restore("""{"days": [{"date": "2026-09-11", "status": "alcohol_free"}]}""".toByteArray(), database, prefs)
        val row = database.rows().day(day.number)!!
        assertTrue(row.isAlcoholFree && row.costOverride == 12.0)
    }

    @Test fun importsDailyTotalsFromAnotherApp() = runBlocking {
        val prefs = prefs()
        val database = database()
        val json = """
            {"days": [
                {"date": "2026-09-12", "status": "drank", "units": 30.6, "kcal": 2696, "cost": 42.0},
                {"date": "2026-09-11", "status": "alcohol_free"}
            ]}
        """.trimIndent()
        assertEquals(1, Exporter.restore(json.toByteArray(), database, prefs))
        val ledger = Ledger(database.rows().days(), prefs.current().clock)
        val saturday = DayKey.of(2026, 9, 12)
        assertTrue(near(ledger.totals(saturday).units, 30.6, 0.001))
        assertEquals(2696.0, ledger.totals(saturday).kcal, 0.0)
        assertEquals(DayStatus.ALCOHOL_FREE, ledger.status(saturday - 1))
    }
}

/**
 * The catalogue is a hand-written table, so guard the mistakes hand-writing makes: a stray decimal point, a brand
 * listed twice, a serve with no size.
 */
class CatalogTests {
    /**
     * What a strength can plausibly be for each kind of drink: wide enough for Żywiec Porter, Wray & Nephew and a 25 ml
     * measure dropped in a glass of Monster, tight enough to catch 45% for 4.5%.
     */
    private fun band(category: DrinkCategory): ClosedFloatingPointRange<Double> = when (category) {
        DrinkCategory.BEER, DrinkCategory.STOUT -> 2.0..13.0
        DrinkCategory.CIDER -> 2.0..9.0
        DrinkCategory.RED_WINE, DrinkCategory.WHITE_WINE, DrinkCategory.ROSE -> 8.0..16.0
        DrinkCategory.BUBBLES -> 5.0..14.0
        // Down to umeshu and Bulgarian pelin, the fruit and aromatised wines filed alongside vermouth and sake.
        DrinkCategory.FORTIFIED -> 10.0..22.0
        DrinkCategory.SPIRIT -> 10.0..85.0
        DrinkCategory.ALCOPOP -> 3.0..9.0
        DrinkCategory.COCKTAIL -> 2.0..35.0
        DrinkCategory.UNITS -> 100.0..100.0
    }

    @Test fun strengthsArePlausibleForTheirKind() {
        for (brand in Catalog.brands) {
            assertTrue("${brand.name} at ${brand.abv}%", brand.abv in band(brand.category))
        }
    }

    @Test fun everyBrandIsListedOnceAndHasSizes() {
        assertEquals(Catalog.brands.size, Catalog.brands.map { it.name }.toSet().size)
        assertEquals(Catalog.items.size, Catalog.items.map { it.id }.toSet().size)
        assertTrue(Catalog.brands.all { it.prices.isNotEmpty() && it.prices.values.all { serves -> serves.isNotEmpty() } })
        // The ceiling is a white cider bottle, the one serve that isn't a glassful.
        assertTrue(Catalog.items.all { it.volumeMl >= 10 && it.volumeMl <= 2500 })
    }

    @Test fun searchFindsBrandsAndKinds() {
        assertTrue(Catalog.search("stella").any { it.name == "Stella Artois" })
        assertTrue(Catalog.search("Red wine").all { it.category == DrinkCategory.RED_WINE })
        assertTrue(Catalog.search("  ").isEmpty())
    }

    /** Every brand of the iOS table made it across, accents and all, and a search without them still finds them. */
    @Test fun theWholeTableIsHere() {
        assertEquals(1168, Catalog.brands.size)
        assertTrue(Catalog.search("lowenbrau").any { it.name == "Löwenbräu Original" })
    }
}

/**
 * The `pour` table is the only one that grows without bound, a row per drink. Every other table holds a few hundred
 * rows at most, where a scan costs nothing and an index would only slow writes. This checks that the two indexes that
 * matter exist and that SQLite uses them.
 */
@RunWith(RobolectricTestRunner::class)
class IndexTests {
    private fun rows(sql: String): List<String> {
        val cursor = database().openHelper.readableDatabase.query(sql)
        return cursor.use { generateSequence { if (it.moveToNext()) it.getString(it.getColumnIndexOrThrow("detail")) else null }.toList() }
    }

    @Test fun pourIsIndexedOnTheColumnsItIsQueriedBy() {
        val db = database().openHelper.readableDatabase
        val indexes = db.query("PRAGMA index_list(pour)").use { generateSequence { if (it.moveToNext()) it.getString(it.getColumnIndexOrThrow("name")) else null }.toList() }
        val columns = indexes.flatMap { index ->
            db.query("PRAGMA index_info(`$index`)").use { generateSequence { if (it.moveToNext()) it.getString(it.getColumnIndexOrThrow("name")) else null }.toList() }
        }
        assertTrue("day" in columns)
        assertTrue("drinkId" in columns)
    }

    @Test fun theDayRangeAndTheDrinkLookupBothUseAnIndex() {
        val plans = listOf(
            rows("EXPLAIN QUERY PLAN SELECT * FROM pour WHERE day BETWEEN 1 AND 7"),
            rows("EXPLAIN QUERY PLAN SELECT COUNT(*) FROM pour WHERE drinkId = x'00'"),
        ).map { it.joinToString(" ") }
        // "USING COVERING INDEX" also counts: it is a better plan on the same index.
        assertTrue("$plans", plans.all { it.contains("SEARCH pour USING") })
        assertTrue("$plans", plans.none { it.contains("SCAN pour") })
    }

    @Test fun entriesComeBackInIndexOrderWithoutASort() {
        // The same query `Queries.entries` makes.
        val plan = rows("EXPLAIN QUERY PLAN SELECT * FROM pour WHERE day BETWEEN 1 AND 7 ORDER BY day, timestamp").joinToString(" ")
        assertTrue(plan, plan.contains("pour_on_day_timestamp"))
        assertFalse(plan, plan.contains("TEMP B-TREE"))
    }
}

class BudgetTextTests {
    @Test fun overReadsAsHowFarOverNotANegativeLeft() {
        assertEquals("2.5 of 4.5 left", 2.0.leftText(4.5))
        assertEquals("1.3 over 4.5", 5.8.leftText(4.5))
        assertEquals("0.0 of 4.5 left", 4.5.leftText(4.5))
    }
}
