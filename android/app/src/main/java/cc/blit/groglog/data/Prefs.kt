package cc.blit.groglog.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import cc.blit.groglog.model.Catalog
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.GoalSerializer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/** The settings that belong to the log (when a day ends, the currency prices are in, the taper) and how it looks. */
data class Settings(
    val rolloverHour: Int = 5,
    val currency: String = Catalog.defaultCurrency(),
    val goal: Goal = Goal(),
) {
    val clock: DayClock get() = DayClock(rolloverHour)
}

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

    suspend fun current(): Settings = settings.first()

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

    private companion object {
        val ROLLOVER_HOUR = intPreferencesKey("rolloverHour")
        val CURRENCY = stringPreferencesKey("currency")
        val GOAL = stringPreferencesKey("goal")
        val DYNAMIC_COLOUR = booleanPreferencesKey("dynamicColour")
    }
}
