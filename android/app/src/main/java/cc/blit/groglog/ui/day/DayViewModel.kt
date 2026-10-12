package cc.blit.groglog.ui.day

import android.text.format.DateFormat
import androidx.compose.runtime.Immutable
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.createSavedStateHandle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import cc.blit.groglog.container
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Queries
import cc.blit.groglog.data.Settings
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Vessel
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** One day as the Day screen shows it. Everything else on the screen is derived from these. */
@Immutable
data class DayState(
    val day: DayKey,
    val ledger: Ledger,
    val settings: Settings,
    /** The week before `day` and the day itself, which the chart compares. */
    val entries: List<Entry>,
    val now: Instant,
) {
    val status: DayStatus get() = ledger.status(day)
    val budget: Double? get() = ledger.dailyBudget(day, settings.goal)
    val totals get() = ledger.totals(day)
    val spendOverride: Double? get() = ledger.spendOverride(day)
    val isToday: Boolean get() = day >= ledger.today

    /** The day's own drinks, latest first. */
    val drinks: List<Entry> get() = entries.filter { it.day == day.number }.asReversed()

    fun title(locale: Locale = Locale.getDefault()): String = when (day) {
        ledger.today -> "Today"
        ledger.today - 1 -> "Yesterday"
        else -> day.localDate.format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "EEEdMMM"), locale))
    }
}

/**
 * A day with previous and next. The day shown is kept in saved state; none means today, so a Day tab left open
 * overnight moves on to the new day at the rollover.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class DayViewModel(
    private val saved: SavedStateHandle,
    queries: Queries,
    prefs: Prefs,
    private val logbook: suspend () -> Logbook,
    now: Flow<Instant> = minutes(),
) : ViewModel() {
    private val selected = saved.getStateFlow<Int?>(DAY, null)

    private val day: Flow<DayKey> = combine(prefs.settings, now, selected) { settings, _, selected ->
        selected?.let(::DayKey)?.coerceAtMost(settings.clock.today) ?: settings.clock.today
    }.distinctUntilChanged()

    /** Entries arrive tagged with the day they were fetched for, so the state never pairs one day with another's window. */
    private val window = day.flatMapLatest { day ->
        queries.entries((day - 7)..day).map { day to it }
    }

    val state: StateFlow<DayState?> = combine(prefs.settings, queries.days(), now, window) { settings, days, now, (day, entries) ->
        DayState(day, Ledger(days, settings.clock), settings, entries, now)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    /** Shows `day`, or today for none or anything later. */
    fun show(day: DayKey?) {
        saved[DAY] = day?.number
    }

    fun previous() {
        state.value?.let { show(it.day - 1) }
    }

    fun next() {
        val state = state.value ?: return
        show((state.day + 1).takeIf { it < state.ledger.today })
    }

    fun setAlcoholFree(dry: Boolean, day: DayKey) = write { setAlcoholFree(dry, day) }

    fun setSpend(amount: Double?, day: DayKey) = write { setSpend(amount, day) }

    fun delete(pour: Pour) = write { delete(pour) }

    fun update(pour: Pour, time: Instant, vessel: Vessel, volumeMl: Double, price: Double, abvOverride: Double?) =
        write { update(pour, time, vessel, volumeMl, price, abvOverride) }

    private fun write(body: suspend Logbook.() -> Unit) {
        viewModelScope.launch { logbook().body() }
    }

    companion object {
        private const val DAY = "day"

        val Factory = viewModelFactory {
            initializer {
                val container = this[APPLICATION_KEY]!!.container
                DayViewModel(createSavedStateHandle(), container.queries, container.prefs, container::logbook)
            }
        }

        /** Ticks on each minute, to move the chart's "now" along and the day on at the rollover. */
        fun minutes(): Flow<Instant> = flow {
            while (true) {
                val now = Instant.now()
                emit(now)
                delay(60_000 - now.toEpochMilli() % 60_000)
            }
        }
    }
}
