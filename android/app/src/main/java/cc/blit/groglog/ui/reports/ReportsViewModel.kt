package cc.blit.groglog.ui.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cc.blit.groglog.AppContainer
import cc.blit.groglog.model.DayRange
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Nights
import cc.blit.groglog.ui.ledgerState
import cc.blit.groglog.data.Seed
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.stateIn

data class ReportsState(
    val ledger: Ledger,
    val goal: Goal,
    val currency: String,
    val nights: Nights,
    /** Drinks from the start of last month or three weeks before this one, whichever is earlier, for the running totals. */
    val entries: List<Entry>,
)

/** The range the running totals need drinks for: this week and the three before it, and this month and the last. */
fun runningRange(ledger: Ledger): DayRange {
    val today = ledger.today
    return minOf(ledger.clock.weekStart(today) - 21, (today.monthStart - 1).monthStart)..today
}

@OptIn(ExperimentalCoroutinesApi::class)
class ReportsViewModel(container: AppContainer) : ViewModel() {
    /** Bumped each time the screen comes back, which moves `today` on and fetches last night once the watch has synced. */
    private val resumed = MutableStateFlow(0)

    /** Collected afresh on each return, so a ledger built yesterday does not go on calling yesterday today. */
    private val ledgerState = resumed.flatMapLatest { container.ledgerState() }.distinctUntilChanged()
    private val ledger = ledgerState.map { it.ledger }.distinctUntilChanged()

    /** Demo mode draws sample readings that follow its sample log, as on iOS, and never asks Health Connect. */
    private val nights = if (container.isDemo) {
        ledger.map(Seed::nights)
    } else {
        combine(container.prefs.settings.map { it.clock }, container.prefs.health, resumed) { clock, switches, _ ->
            Triple(clock, switches.heart, switches.sleep)
        }.mapLatest { (clock, heart, sleep) -> container.health.nights(clock, heart, sleep) }
            .onStart { emit(Nights()) }
    }

    private val entries = ledger.map(::runningRange).distinctUntilChanged().flatMapLatest { container.queries.entries(it) }

    val state: StateFlow<ReportsState?> = combine(ledgerState, nights, entries) { ledgerState, nights, entries ->
        ReportsState(ledgerState.ledger, ledgerState.settings.goal, ledgerState.settings.currency, nights, entries)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    private val _weeks = MutableStateFlow(12)

    /** How many weeks the weekly bars show at once. */
    val weeks: StateFlow<Int> = _weeks.asStateFlow()

    private val _shownHeart = MutableStateFlow(HeartReading.HRV)

    /** Which heart reading the charts draw, shared by all of them. */
    val shownHeart: StateFlow<HeartReading> = _shownHeart.asStateFlow()

    fun resume() {
        resumed.value += 1
    }

    fun showWeeks(weeks: Int) {
        _weeks.value = weeks
    }

    fun showHeart(reading: HeartReading) {
        _shownHeart.value = reading
    }
}
