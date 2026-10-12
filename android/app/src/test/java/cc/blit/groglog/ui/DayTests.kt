package cc.blit.groglog.ui

import cc.blit.groglog.beer
import cc.blit.groglog.clock
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Settings
import cc.blit.groglog.database
import cc.blit.groglog.date
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.DayTotals
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.Units
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.prefs
import cc.blit.groglog.ui.day.ChartSeries
import cc.blit.groglog.ui.day.DayState
import cc.blit.groglog.ui.day.DayViewModel
import cc.blit.groglog.ui.day.dayChart
import cc.blit.groglog.ui.day.unitTicks
import cc.blit.groglog.model.CurvePoint
import androidx.compose.ui.graphics.Color
import java.time.Instant
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** What `AppContainer.ledgerState` gives, over a test database and settings. */
fun ledgerState(database: AppDatabase, prefs: Prefs) =
    combine(prefs.settings, database.queries().days()) { settings, days -> LedgerState(settings, Ledger(days, settings.clock)) }

/** A day's drinks at given hours after the day starts, and the ledger over them. */
private fun week(vararg drinks: Pair<DayKey, Double>): Pair<Ledger, List<Entry>> {
    val drink = beer()
    val entries = drinks.map { (day, hours) ->
        Entry(Pour(drinkId = drink.id, timestamp = clock.start(day).plusSeconds((hours * 3600).toLong()), day = day.number, vessel = Vessel.PINT, volumeMl = 568.0, price = 5.0), drink)
    }
    val days = entries.groupBy { it.day }.map { (number, list) -> Day(number).with(DayTotals.of(list)) }
    return Ledger(days, clock) to entries
}

class DayChartTests {
    private val day = DayKey.of(2026, 3, 10)

    @Test fun startsOnTheHourBeforeTheFirstDrinkOfTheThreeDays() {
        val (ledger, entries) = week(day to 13.5, (day - 2) to 11.25)
        val chart = dayChart(day, ledger, null, entries, Instant.now(), Locale.UK)
        assertEquals(10.0, chart.from, 0.0)
        assertEquals(listOf(10.0, 13.0, 16.0, 19.0, 22.0), chart.ticks.map { it.first })
        assertEquals("15", chart.ticks.first().second)
    }

    @Test fun anEmptyDayStartsInTheAfternoon() {
        val (ledger, entries) = week()
        assertEquals(9.0, dayChart(day, ledger, null, entries, Instant.now()).from, 0.0)
    }

    @Test fun anEarlyDrinkStartsTheChartAtTheDaysStart() {
        val (ledger, entries) = week(day to 0.5)
        assertEquals(0.0, dayChart(day, ledger, null, entries, Instant.now()).from, 0.0)
    }

    @Test fun aDayNotLoggedIsLeftOffRatherThanDrawnAsZero() {
        val (ledger, entries) = week(day to 15.0, (day - 2) to 15.0)
        val chart = dayChart(day, ledger, null, entries, Instant.now(), Locale.UK)
        assertTrue(chart.series[1].points.isEmpty())
        assertNull(chart.series[1].value(24.0))
        assertEquals("Sun", chart.series[2].name)
        assertEquals(2.84, chart.series[2].value(24.0)!!, 0.001)
    }

    @Test fun aPastDayHasNoNowAndReadsAtTheEnd() {
        val (ledger, entries) = week(day to 15.0, day to 16.0)
        val chart = dayChart(day, ledger, 4.0, entries, Instant.now())
        assertNull(chart.nowHour)
        assertEquals(24.0, chart.at, 0.0)
        assertEquals(5.68, chart.today.value(chart.at)!!, 0.001)
        assertEquals(5.68 * 1.1, chart.top, 0.001)
        assertTrue(chart.spoken.startsWith("Today 5.7 units"))
        assertTrue(chart.spoken.endsWith("budget 4.0"))
    }

    @Test fun theWeeksFigureIsTheRealMeanNotTheSmoothedLine() {
        val (ledger, entries) = week(day to 15.0, (day - 1) to 15.0, (day - 1) to 15.5)
        val average = dayChart(day, ledger, null, entries, Instant.now()).series[3]
        // One logged day in the week before, so the mean by 3:15pm is both its drinks.
        assertEquals(5.68, average.value(15.5)!!, 0.001)
        assertTrue(average.points.first { it.x == 15.5 }.units < 5.68)
    }

    @Test fun aSeriesReadsZeroBeforeItsFirstPoint() {
        val series = ChartSeries("Today", Color.Red, listOf(CurvePoint(10.0, 1.0)))
        assertEquals(0.0, series.value(9.0)!!, 0.0)
        assertEquals(1.0, series.value(11.0)!!, 0.0)
    }

    @Test fun theUnitsAxisStepsInRoundNumbers() {
        assertEquals(listOf(0.0, 1.0, 2.0), unitTicks(2.2))
        assertEquals(listOf(0.0, 1.0, 2.0, 3.0, 4.0), unitTicks(4.4))
        assertEquals(listOf(0.0, 2.0, 4.0, 6.0, 8.0), unitTicks(8.8))
        assertEquals(listOf(0.0, 5.0, 10.0), unitTicks(13.2))
    }

}

@RunWith(RobolectricTestRunner::class)
class DayStateTests {
    private val today = clock.today

    @Test fun titlesNameTheRecentDaysAndDateTheRest() {
        val (ledger, entries) = week()
        fun title(day: DayKey) = DayState(day, ledger, Settings(), entries, Instant.now()).title(Locale.UK)
        assertEquals("Today", title(today))
        assertEquals("Yesterday", title(today - 1))
        val older = DayKey.of(2026, 3, 10)
        assertEquals("Tue 10 Mar", title(older))
    }

    @Test fun drinksAreTheDaysOwnLatestFirst() {
        val (ledger, entries) = week(today to 14.0, today to 16.0, (today - 1) to 15.0)
        val state = DayState(today, ledger, Settings(), entries, Instant.now())
        assertEquals(2, state.drinks.size)
        assertTrue(state.drinks[0].timestamp > state.drinks[1].timestamp)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class DayViewModelTests {
    @Before fun main() = Dispatchers.setMain(Dispatchers.Unconfined)
    @After fun reset() = Dispatchers.resetMain()

    private fun model(prefs: Prefs = prefs()): Pair<DayViewModel, suspend () -> Logbook> {
        val database = database()
        val logbook: suspend () -> Logbook = { Logbook(database, prefs.current().clock) }
        return DayViewModel(ledgerState(database, prefs), database.queries(), logbook, now = flowOf(Instant.now())) to logbook
    }

    private suspend fun DayViewModel.until(test: (DayState) -> Boolean): DayState =
        withTimeout(10_000) { state.first { it != null && test(it) }!! }

    @Test fun opensOnTodayAndPagesNoFurther() = runBlocking {
        val (model, _) = model()
        val today = model.until { true }.ledger.today
        assertEquals(today, model.until { true }.day)
        model.next()
        assertEquals(today, model.until { true }.day)
        model.previous()
        assertEquals("Yesterday", model.until { it.day == today - 1 }.title())
        model.next()
        model.until { it.day == today }
        model.show(today + 3)
        assertEquals(today, model.until { true }.day)
    }

    @Test fun marksADayDryAndBack() = runBlocking {
        val (model, _) = model()
        val day = model.until { true }.ledger.today - 2
        model.show(day)
        assertEquals(DayStatus.UNTRACKED, model.until { it.day == day }.status)
        model.setAlcoholFree(true, day)
        model.until { it.status == DayStatus.ALCOHOL_FREE }
        model.setAlcoholFree(false, day)
        model.until { it.status == DayStatus.UNTRACKED }
        Unit
    }

    @Test fun editsSetsTheSpendAndDeletes() = runBlocking {
        val (model, logbook) = model()
        val day = model.until { true }.ledger.today - 1
        val drink = beer()
        logbook().rows.insert(drink)
        val time = logbook().clock.start(day).plusSeconds(16 * 3600)
        logbook().log(Serve(drink), listOf(time))
        model.show(day)
        val entry = model.until { it.day == day && it.drinks.size == 1 }.drinks.single()

        logbook().update(entry.pour, time.plusSeconds(1800), Vessel.HALF, 284.0, 3.0, 5.5)
        // Entries and day totals are separate observations; the edit has landed once both show it.
        val edited = model.until { it.drinks.singleOrNull()?.volumeMl == 284.0 && it.totals.cost == 3.0 }
        assertEquals(5.5, edited.drinks.single().abv, 0.0)
        assertEquals(Units.of(284.0, 5.5), edited.totals.units, 0.0001)
        assertNull(edited.spendOverride)

        model.setSpend(20.0, day)
        assertEquals(20.0, model.until { it.spendOverride != null }.totals.cost, 0.0)
        model.setSpend(null, day)
        assertEquals(3.0, model.until { it.spendOverride == null }.totals.cost, 0.0)

        model.delete(edited.drinks.single().pour)
        val emptied = model.until { it.drinks.isEmpty() && it.totals.count == 0 }
        assertEquals(0.0, emptied.totals.units, 0.0)
    }

    @Test fun theWindowIsTheWeekBeforeAndTheDay() = runBlocking {
        val (model, logbook) = model()
        val today = model.until { true }.ledger.today
        val drink = beer()
        logbook().rows.insert(drink)
        val clock = logbook().clock
        for (back in 0..8) logbook().log(Serve(drink), listOf(clock.start(today - back).plusSeconds(15 * 3600)))
        val state = model.until { it.entries.size == 8 }
        assertEquals((today - 7).number, state.entries.minOf { it.day })
    }
}
