package cc.blit.groglog.ui.calendar

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cc.blit.groglog.AppContainer
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.LedgerState
import cc.blit.groglog.ui.day.DayViewModel
import cc.blit.groglog.ui.ledgerState
import cc.blit.groglog.ui.theme.HeatBand
import java.time.Instant
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
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

@OptIn(ExperimentalCoroutinesApi::class)
class CalendarViewModel(
    ledgerState: Flow<LedgerState>,
    private val logbook: suspend () -> Logbook,
    now: Flow<Instant> = DayViewModel.minutes(),
) : ViewModel() {
    constructor(container: AppContainer) : this(container.ledgerState(), container::logbook)

    /** Read afresh each minute, so today moves on at the rollover even when nothing is logged. */
    val state: StateFlow<CalendarState?> = now.flatMapLatest { ledgerState }
        .map { CalendarState(it.ledger, it.settings.goal) }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    fun setAlcoholFree(dry: Boolean, day: DayKey) {
        viewModelScope.launch { logbook().setAlcoholFree(dry, day) }
    }
}
