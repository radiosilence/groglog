package cc.blit.groglog.export

import androidx.room.withTransaction
import cc.blit.groglog.core.BackupDoc
import cc.blit.groglog.core.BackupException
import cc.blit.groglog.core.ExportDrink
import cc.blit.groglog.core.ExportEntry
import cc.blit.groglog.core.ExportFavourite
import cc.blit.groglog.core.ExportInput
import cc.blit.groglog.core.MarkdownFormat
import cc.blit.groglog.core.RestoreOp
import cc.blit.groglog.core.RestoreSnapshot
import cc.blit.groglog.core.SnapshotDrink
import cc.blit.groglog.core.SnapshotFavourite
import cc.blit.groglog.core.backupBuild
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Settings
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Favourite
import cc.blit.groglog.model.GoalSerializer
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.model.abvText
import cc.blit.groglog.model.money
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.model.volumeText
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class ImportException(message: String) : Exception(message) {
    companion object {
        fun dayEndsAtImpossibleHour(hour: Int) = ImportException("The file sets the day to end at hour $hour, which is not an hour of the day.")
        fun tooLarge() = ImportException("The file is too large to be a GrogLog backup.")
    }
}

/**
 * The backup document is the shared core's: its format, the assembly of an export and the planning of a restore. This
 * reads the database into what the core asks for, and applies the plan it gives back. Days are listed explicitly,
 * including unlogged ones, so a reader (human or LLM) can tell a dry day from a gap. Import is lenient: only
 * `days[].date` and `days[].status` are required, so other apps' data can be hand-converted (see docs/IMPORT.md). The
 * format is the iOS app's, byte for byte.
 */
object Exporter {
    enum class Kind(val extension: String, val mimeType: String) { JSON("json", "application/json"), MARKDOWN("md", "text/markdown") }

    suspend fun backup(database: AppDatabase, settings: Settings): BackupDoc = database.withTransaction {
        val rows = Logbook(database, settings.clock).rows
        val clock = settings.clock
        backupBuild(
            ExportInput(
                exportedAt = Instant.now().epochSecond,
                rolloverHour = settings.rolloverHour.toLong(),
                currency = settings.currency,
                goalJson = GoalSerializer.encode(settings.goal).toString(),
                goal = settings.goal.spec(DayKey.of(settings.goal.start, clock.zone)),
                today = clock.today.number.toLong(),
                firstWeekday = clock.firstWeekday.toLong(),
                days = rows.days().map { it.core },
                entries = rows.entriesByTime().map {
                    ExportEntry(
                        it.id.toString(), it.timestamp.epochSecond, it.day.toLong(), it.name, it.category.kind, it.vessel.kind,
                        it.volumeMl, it.abv, it.units, it.kcal, it.price, it.drink.id.toString(),
                    )
                },
                drinks = rows.drinksByName().map {
                    ExportDrink(it.id.toString(), it.name, it.category.kind, it.abv, it.vessel.kind, it.volumeMl, it.price, it.isGeneric, it.isHidden)
                },
                favourites = rows.favouritesInOrder().map {
                    ExportFavourite(it.drinkId.toString(), it.vessel.kind, it.volumeMl, it.price, it.sortOrder.toLong())
                },
            ),
        )
    }

    /** UTF-8 JSON, laid out exactly as iOS lays it out. */
    fun json(backup: BackupDoc): ByteArray = backup.json()

    fun decode(data: ByteArray): BackupDoc =
        try {
            BackupDoc.parse(data)
        } catch (error: BackupException.DayEndsAtImpossibleHour) {
            // An hour outside 0-23 would break every date the clock builds, so the file is refused.
            throw ImportException.dayEndsAtImpossibleHour(error.hour.toInt())
        }

    /** `groglog-2026-10-12.json`, dated by the drinking day. */
    fun fileName(kind: Kind, settings: Settings) = "groglog-${settings.clock.today}.${kind.extension}"

    /** A compact, readable log meant for pasting into a chat with an LLM. */
    fun markdown(backup: BackupDoc, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String =
        backup.markdown(Instant.now().epochSecond, Reader(zone, locale))

    /** How a reader of the markdown sees numbers and dates: in this phone's language and region. */
    private class Reader(zone: ZoneId, private val locale: Locale) : MarkdownFormat {
        private val dateTime = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(locale).withZone(zone)
        private val date = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).withZone(zone)
        private val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).withZone(zone)

        override fun units(value: Double) = value.unitsText
        override fun money(value: Double, currency: String) = value.money(currency)
        override fun volume(ml: Double) = ml.volumeText
        override fun abv(abv: Double) = abv.abvText
        override fun dateTime(seconds: Long): String = dateTime.format(Instant.ofEpochSecond(seconds))
        override fun date(seconds: Long): String = date.format(Instant.ofEpochSecond(seconds))
        override fun time(seconds: Long): String = time.format(Instant.ofEpochSecond(seconds))
    }

    /**
     * Merges a backup in one transaction without modifying existing data: drinks and entries are matched by id, and a
     * day that already has drinks keeps them. Entries are placed under the file's day end, so they land on the correct
     * days, and the file's settings are written once the merge has committed. Totals are recomputed for only the
     * touched days. Returns how many entries were added. Throws, having written nothing, for a file it cannot read.
     */
    suspend fun restore(data: ByteArray, database: AppDatabase, prefs: Prefs): Int {
        val backup = withContext(Dispatchers.Default) { decode(data) }
        val goal = backup.goalJson()?.let(GoalSerializer::decode)
        val before = prefs.current()
        val hour = backup.dayStartsAtHour()?.toInt() ?: before.rolloverHour
        // Entries are placed under the file's day end, but the settings are written only once they have committed, so
        // a file that fails partway leaves the settings as they were along with the log.
        val logbook = Logbook(database, DayClock(hour))
        val clock = logbook.clock
        var added = 0

        logbook.bulk { rows ->
            val plan = backup.plan(
                RestoreSnapshot(
                    today = clock.today.number.toLong(),
                    drinks = rows.drinks().map { SnapshotDrink(it.id.toString(), it.name, it.category.kind, it.abv) },
                    favourites = rows.favourites().map { SnapshotFavourite(it.drinkId.toString(), it.vessel.kind, it.volumeMl) },
                    pourIds = rows.pourIds().map { it.toString() },
                    daysWithPours = rows.daysWithPours().map { it.toLong() },
                ),
            )
            val evenings = HashMap<Int, Instant>()
            for (op in plan.ops) {
                when (op) {
                    is RestoreOp.InsertDrink -> rows.insert(
                        Drink(
                            UUID.fromString(op.id), op.name, DrinkCategory.of(op.category), op.abv, Vessel.of(op.vessel),
                            op.volumeMl, op.price, op.isGeneric, op.isHidden, op.sortOrder.toInt(),
                        ),
                    )
                    is RestoreOp.InsertFavourite -> rows.insert(
                        Favourite(drinkId = UUID.fromString(op.drinkId), vessel = Vessel.of(op.vessel), volumeMl = op.volumeMl, price = op.price, sortOrder = op.sortOrder.toInt()),
                    )
                    is RestoreOp.MarkAlcoholFree -> rows.save((rows.day(op.day.toInt()) ?: Day(op.day.toInt())).copy(isAlcoholFree = true))
                    is RestoreOp.SetSpend -> rows.save((rows.day(op.day.toInt()) ?: Day(op.day.toInt())).copy(costOverride = op.amount))
                    is RestoreOp.InsertPour -> {
                        val timestamp = op.time?.let(Instant::ofEpochSecond)
                            ?: evenings.getOrPut(op.day.toInt()) { clock.suggestedTime(DayKey(op.day.toInt()), null) }.plusSeconds(op.eveningOffsetMinutes * 60)
                        rows.insert(
                            Pour(
                                UUID.fromString(op.id), UUID.fromString(op.drinkId), timestamp, op.day.toInt(), Vessel.of(op.vessel),
                                op.volumeMl, op.price, op.kcalOverride, op.abvOverride,
                            ),
                        )
                    }
                }
            }
            added = plan.added.toInt()
            plan.touched.map { DayKey(it.toInt()) }.toSet()
        }
        backup.currency()?.let { prefs.setCurrency(it) }
        goal?.let { prefs.setGoal(it) }
        // Existing entries were assigned days by the old hour and imported ones by the new one, so every day is
        // reassigned.
        if (hour != before.rolloverHour) prefs.moveDayEnd(hour, database)
        return added
    }
}
