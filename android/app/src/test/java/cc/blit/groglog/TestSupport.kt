package cc.blit.groglog

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.test.core.app.ApplicationProvider
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayRange
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Vessel
import java.io.File
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

val london: ZoneId = ZoneId.of("Europe/London")

/** Days end at 5am in London, weeks start on Monday. */
val clock = DayClock(rolloverHour = 5, zone = london, firstWeekday = 2)

fun date(y: Int, m: Int, d: Int, h: Int = 0, min: Int = 0): Instant = LocalDateTime.of(y, m, d, h, min).atZone(london).toInstant()

fun database(): AppDatabase = AppDatabase.inMemory(ApplicationProvider.getApplicationContext())

fun beer(abv: Double = 5.0, ml: Double = 568.0) =
    Drink(name = "Beer", category = DrinkCategory.BEER, abv = abv, vessel = Vessel.PINT, volumeMl = ml, price = 5.0)

/** A fresh in-memory database with one drink, and a logbook over it. */
suspend fun logbook(drink: Drink = beer()): Pair<Logbook, Drink> {
    val logbook = Logbook(database(), clock)
    logbook.rows.insert(drink)
    return logbook to drink
}

suspend fun ledger(logbook: Logbook) = Ledger(logbook.rows.days(), clock)

suspend fun entries(logbook: Logbook, days: DayRange): List<Entry> =
    logbook.rows.entries(days.start.number, days.endInclusive.number)

/** Settings in a file of their own, as a fresh install has them. */
fun prefs(): Prefs {
    val file = File(System.getProperty("java.io.tmpdir"), "groglog-test-${UUID.randomUUID()}.preferences_pb")
    file.deleteOnExit()
    return Prefs(PreferenceDataStoreFactory.create(scope = CoroutineScope(Dispatchers.IO + SupervisorJob())) { file })
}

fun near(a: Double, b: Double, tolerance: Double = 0.0001) = kotlin.math.abs(a - b) < tolerance
