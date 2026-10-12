package cc.blit.groglog.ui.calendar

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import cc.blit.groglog.container
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Queries
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.day.DayViewModel
import cc.blit.groglog.ui.theme.HeatBand
import java.time.Instant
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@Immutable
data class CalendarState(val ledger: Ledger, val goal: Goal) {
    /**
     * Every month from the first logged to this one, oldest first, and never fewer than three, so a new log still
     * shows where it is going.
     */
    val months: List<DayKey>
        get() {
            val thisMonth = ledger.today.monthStart
            val twoBack = ((thisMonth - 1).monthStart - 1).monthStart
            val first = minOf(ledger.firstDay?.monthStart ?: thisMonth, twoBack)
            return generateSequence(first) { it + it.daysInMonth }.takeWhile { it <= thisMonth }.toList()
        }

    fun cells(month: DayKey): List<DayCellState> = (month..(month + month.daysInMonth - 1)).map { day ->
        DayCellState(day, ledger.status(day), ledger.totals(day).units, ledger.dailyBudget(day, goal), day == ledger.today)
    }

    /** Blank cells before the first of the month, so it falls under its weekday. */
    fun leadingBlanks(month: DayKey): Int = (month.weekday - ledger.clock.firstWeekday + 7) % 7
}

/** One day as its cell shows it, on plain values, so a commit that changes another day leaves this one alone. */
@Immutable
data class DayCellState(val day: DayKey, val status: DayStatus, val units: Double, val budget: Double?, val isToday: Boolean) {
    val heat: HeatBand get() = HeatBand.of(units, budget)

    val spoken: String
        get() = when (status) {
            DayStatus.DRANK -> "${units.unitsText} units" + (budget?.let { ", ${HeatBand.of(units, it).spoken}" } ?: "")
            DayStatus.ALCOHOL_FREE -> "Alcohol-free"
            DayStatus.UNLOGGED -> "Not logged"
            DayStatus.TODAY -> "Nothing logged yet"
            DayStatus.FUTURE, DayStatus.UNTRACKED -> ""
        }
}

class CalendarViewModel(
    queries: Queries,
    prefs: Prefs,
    private val logbook: suspend () -> Logbook,
    now: Flow<Instant> = DayViewModel.minutes(),
) : ViewModel() {
    val state: StateFlow<CalendarState?> = combine(prefs.settings, queries.days(), now) { settings, days, _ ->
        CalendarState(Ledger(days, settings.clock), settings.goal)
    }.distinctUntilChanged().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    fun setAlcoholFree(dry: Boolean, day: DayKey) {
        viewModelScope.launch { logbook().setAlcoholFree(dry, day) }
    }

    companion object {
        val Factory = viewModelFactory {
            initializer {
                val container = this[APPLICATION_KEY]!!.container
                CalendarViewModel(container.queries, container.prefs, container::logbook)
            }
        }
    }
}
