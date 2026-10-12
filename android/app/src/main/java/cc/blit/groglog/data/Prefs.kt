package cc.blit.groglog.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.preferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import cc.blit.groglog.model.Catalog
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.GoalSerializer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** The settings that belong to the log (when a day ends, the currency prices are in, the taper) and how it looks. */
data class Settings(
    val rolloverHour: Int = 5,
    val currency: String = Catalog.defaultCurrency(),
    val goal: Goal = Goal(),
) {
    val clock: DayClock get() = DayClock(rolloverHour)
}

/**
 * The Health Connect switches. They belong to the device rather than the log, since each device grants its own
 * permissions, so they are kept apart from `Settings`.
 */
data class HealthSwitches(
    /** Each drink's calories are written to Health Connect as it is logged. */
    val copies: Boolean = false,
    /** Overnight HRV, resting heart rate and heart rate while asleep are read for Reports. */
    val heart: Boolean = false,
    /** Sleep by stage is read for Reports. */
    val sleep: Boolean = false,
)

val Context.settingsStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

/**
 * Settings in DataStore. A goal is stored as the JSON iOS writes, read through the same lenient decoder, so a goal from
 * an older build keeps what it set. Changing `rolloverHour` moves entries between days: the caller follows it with
 * `Logbook.rebuild(reassigningDays = true)` under the new clock.
 */
class Prefs(private val store: DataStore<Preferences>) {
    val settings: Flow<Settings> = store.data.map { values ->
        Settings(
            rolloverHour = values[ROLLOVER_HOUR] ?: 5,
            currency = values[CURRENCY] ?: Catalog.defaultCurrency(),
            goal = values[GOAL]?.let { runCatching { GoalSerializer.decode(it) }.getOrNull() } ?: Goal(),
        )
    }.distinctUntilChanged()

    /**
     * Material You's wallpaper colours in place of GrogLog's palette. Kept apart from `settings` because it belongs to
     * this device, as its wallpaper does, so backups leave it out.
     */
    val dynamicColour: Flow<Boolean> = store.data.map { it[DYNAMIC_COLOUR] ?: false }.distinctUntilChanged()
    val health: Flow<HealthSwitches> = store.data.map { values ->
        HealthSwitches(values[COPIES_TO_HEALTH] ?: false, values[READS_HEART] ?: false, values[READS_SLEEP] ?: false)
    }.distinctUntilChanged()

    suspend fun current(): Settings = settings.first()

    suspend fun setHealth(switches: HealthSwitches) {
        store.edit {
            it[COPIES_TO_HEALTH] = switches.copies
            it[READS_HEART] = switches.heart
            it[READS_SLEEP] = switches.sleep
        }
    }

    suspend fun setRolloverHour(hour: Int) {
        require(hour in 0..23) { "Not an hour of the day: $hour" }
        store.edit { it[ROLLOVER_HOUR] = hour }
    }

    suspend fun setCurrency(code: String) {
        store.edit { it[CURRENCY] = code }
    }

    suspend fun setGoal(goal: Goal) {
        store.edit { it[GOAL] = GoalSerializer.encode(goal).toString() }
    }

    suspend fun setDynamicColour(on: Boolean) {
        store.edit { it[DYNAMIC_COLOUR] = on }
    }

    companion object {
        private val ROLLOVER_HOUR = intPreferencesKey("rolloverHour")
        private val CURRENCY = stringPreferencesKey("currency")
        private val GOAL = stringPreferencesKey("goal")
        private val COPIES_TO_HEALTH = booleanPreferencesKey("mirrorsToHealth")
        private val READS_HEART = booleanPreferencesKey("readsHeart")
        private val READS_SLEEP = booleanPreferencesKey("readsSleep")
        private val DYNAMIC_COLOUR = booleanPreferencesKey("dynamicColour")

        /** Demo mode's settings: in memory, starting from the goal iOS's demo store sets, 10% every 7 days. */
        fun demo(): Prefs {
            val goal = Goal(isEnabled = true, reductionPercent = 10.0, periodDays = 7)
            return Prefs(MemoryStore(preferencesOf(GOAL to GoalSerializer.encode(goal).toString())))
        }
    }
}

/** Preferences held in memory only, so whatever demo mode changes is gone when it ends and never reaches the real ones. */
class MemoryStore(initial: Preferences = emptyPreferences()) : DataStore<Preferences> {
    private val state = MutableStateFlow(initial)
    private val lock = Mutex()

    override val data: Flow<Preferences> = state

    override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences =
        lock.withLock { transform(state.value).also { state.value = it } }
}
