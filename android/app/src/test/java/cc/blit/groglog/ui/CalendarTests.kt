package cc.blit.groglog.ui

import cc.blit.groglog.clock
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.database
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.prefs
import cc.blit.groglog.ui.calendar.CalendarState
import cc.blit.groglog.ui.calendar.CalendarViewModel
import cc.blit.groglog.ui.calendar.DayCellState
import cc.blit.groglog.ui.theme.HeatBand
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

class CalendarStateTests {
    private val today = clock.today

    @Test fun aNewLogShowsThisMonthAndTheTwoBefore() {
        val months = CalendarState(Ledger(emptyList(), clock), Goal()).months
        assertEquals(3, months.size)
        assertEquals(today.monthStart, months.last())
        assertTrue(months.all { it.components.day == 1 })
    }

    @Test fun monthsRunFromTheFirstLoggedDay() {
        val first = today.monthStart - 400
        val months = CalendarState(Ledger(listOf(Day(first.number, isAlcoholFree = true)), clock), Goal()).months
        assertEquals(first.monthStart, months.first())
        assertEquals(today.monthStart, months.last())
        assertTrue(months.size in 14..15)
        assertTrue(months.zipWithNext().all { (a, b) -> a + a.daysInMonth == b })
    }

    @Test fun theFirstFallsUnderItsWeekday() {
        // Weeks start on Monday.
        val state = CalendarState(Ledger(emptyList(), clock), Goal())
        assertEquals(0, state.leadingBlanks(DayKey.of(2026, 6, 1)))
        assertEquals(3, state.leadingBlanks(DayKey.of(2026, 10, 1)))
        assertEquals(6, state.leadingBlanks(DayKey.of(2026, 3, 1)))
    }

    @Test fun cellsCarryTheirDaysStatusAndBudget() {
        val day = today - 3
        val ledger = Ledger(listOf(Day(day.number, units = 6.0, count = 2), Day((day + 1).number, isAlcoholFree = true)), clock)
        val cells = CalendarState(ledger, Goal()).cells(day.monthStart).associateBy { it.day }
        assertEquals(DayStatus.DRANK, cells[day]?.status)
        assertEquals(6.0, cells[day]!!.units, 0.0)
        cells[day + 1]?.let { assertEquals(DayStatus.ALCOHOL_FREE, it.status) }
        cells[today]?.let { assertTrue(it.isToday) }
    }

    @Test fun aCellSaysHowFarOverItWas() {
        val day = DayKey.of(2026, 3, 10)
        assertEquals("3.0 units, within budget", DayCellState(day, DayStatus.DRANK, 3.0, 4.0, false).spoken)
        assertEquals("5.0 units, over budget", DayCellState(day, DayStatus.DRANK, 5.0, 4.0, false).spoken)
        assertEquals("6.0 units, well over budget", DayCellState(day, DayStatus.DRANK, 6.0, 4.0, false).spoken)
        assertEquals("6.0 units", DayCellState(day, DayStatus.DRANK, 6.0, null, false).spoken)
        assertEquals("Not logged", DayCellState(day, DayStatus.UNLOGGED, 0.0, null, false).spoken)
        assertEquals(HeatBand.WELL_OVER, DayCellState(day, DayStatus.DRANK, 6.0, 4.0, false).heat)
        assertEquals("!!", DayCellState(day, DayStatus.DRANK, 6.0, 4.0, false).heat.mark)
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class CalendarViewModelTests {
    @Before fun main() = Dispatchers.setMain(Dispatchers.Unconfined)
    @After fun reset() = Dispatchers.resetMain()

    @Test fun aLongPressMarksADryDayAndTheStreakCounts() = runBlocking {
        val database = database()
        val prefs = prefs()
        val model = CalendarViewModel(database.queries(), prefs, { Logbook(database, prefs.current().clock) }, flowOf(Instant.now()))
        suspend fun until(test: (CalendarState) -> Boolean) = withTimeout(10_000) { model.state.first { it != null && test(it) }!! }
        val today = until { true }.ledger.today
        model.setAlcoholFree(true, today - 1)
        model.setAlcoholFree(true, today - 2)
        val state = until { it.ledger.dryStreak() == 2 }
        assertEquals(DayStatus.ALCOHOL_FREE, state.ledger.status(today - 1))
        model.setAlcoholFree(false, today - 1)
        assertEquals(DayStatus.UNLOGGED, until { it.ledger.dryStreak() == 0 }.ledger.status(today - 1))
    }
}
