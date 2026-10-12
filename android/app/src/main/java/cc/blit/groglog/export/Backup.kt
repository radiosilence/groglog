package cc.blit.groglog.export

import androidx.room.withTransaction
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Settings
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.Favourite
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Iso8601Serializer
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Taper
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.model.abvText
import cc.blit.groglog.model.money
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.model.volumeText
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json

/**
 * Everything, as one self-describing document. Days are listed explicitly, including unlogged ones, so a reader (human
 * or LLM) can tell a dry day from a gap. Import is lenient: only `days[].date` and `days[].status` are required, so
 * other apps' data can be hand-converted (see docs/IMPORT.md). The format is the iOS app's, byte for byte.
 */
@Serializable
data class Backup(
    val format: String? = "groglog/1",
    @Serializable(with = Iso8601Serializer::class) val exportedAt: Instant? = Instant.now(),
    val notes: String? = NOTES,
    val dayStartsAtHour: Int? = null,
    val currency: String? = null,
    val goal: Goal? = null,
    /** `yyyy-MM-dd` on which the taper reaches the level at which drinking can stop (`Goal.STOP_FROM`), if followed. */
    val projectedStop: String? = null,
    val drinks: List<DrinkRecord>? = null,
    /** The Log grid: drinks in their usual sizes and prices. */
    val favourites: List<FavouriteRecord>? = null,
    val days: List<DayRecord>,
) {
    /** A drink's identity, with the size and price it was first added at. */
    @Serializable
    data class DrinkRecord(
        @Serializable(with = UuidSerializer::class) val id: UUID,
        val name: String,
        val category: DrinkCategory,
        val abv: Double,
        val vessel: Vessel,
        val volumeMl: Double,
        val price: Double,
        val isGeneric: Boolean,
        val isHidden: Boolean,
    )

    @Serializable
    data class FavouriteRecord(
        @Serializable(with = UuidSerializer::class) val drinkID: UUID,
        val vessel: Vessel,
        val volumeMl: Double,
        val price: Double,
        val order: Int,
    )

    @Serializable
    data class DayRecord(
        val date: String,
        val status: String,
        val units: Double? = null,
        val kcal: Double? = null,
        val cost: Double? = null,
        /** Set when the day's spend was entered manually; `cost` is then that figure rather than the sum of prices. */
        val spentByHand: Double? = null,
        val budget: Double? = null,
        val pours: List<PourRecord>? = null,
    )

    @Serializable
    data class PourRecord(
        @Serializable(with = UuidSerializer::class) val id: UUID? = null,
        @Serializable(with = Iso8601Serializer::class) val time: Instant? = null,
        val name: String,
        val category: DrinkCategory? = null,
        val vessel: Vessel? = null,
        val volumeMl: Double? = null,
        val abv: Double? = null,
        val units: Double? = null,
        val kcal: Double? = null,
        val price: Double? = null,
        @Serializable(with = UuidSerializer::class) val drinkID: UUID? = null,
    )

    companion object {
        const val NOTES = "UK units: 1 unit = 10 ml pure alcohol. Days run from dayStartsAtHour to the same hour next morning. status is drank, alcohol_free (explicitly marked), not_logged (unknown; do not assume dry) or in_progress (today)."
    }
}

/** Ids as iOS writes them: upper case. Either case reads. */
object UuidSerializer : KSerializer<UUID> {
    override val descriptor = PrimitiveSerialDescriptor("cc.blit.groglog.UUID", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: UUID) = encoder.encodeString(value.toString().uppercase(Locale.ROOT))
    override fun deserialize(decoder: Decoder): UUID {
        val string = decoder.decodeString()
        return runCatching { UUID.fromString(string) }.getOrNull()?.takeIf { string.length == 36 }
            ?: throw SerializationException("Expected a UUID, got $string")
    }
}

class ImportException(message: String) : Exception(message) {
    companion object {
        fun dayEndsAtImpossibleHour(hour: Int) = ImportException("The file sets the day to end at hour $hour, which is not an hour of the day.")
        fun tooLarge() = ImportException("The file is too large to be a GrogLog backup.")
    }
}

object Exporter {
    enum class Kind(val extension: String, val mimeType: String) { JSON("json", "application/json"), MARKDOWN("md", "text/markdown") }

    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
    }

    suspend fun backup(database: AppDatabase, settings: Settings): Backup = database.withTransaction {
        val rows = Logbook(database, settings.clock).rows
        val ledger = Ledger(rows.days(), settings.clock)
        val byDay = rows.entriesByTime().groupBy { it.day }
        val first = ledger.firstDay
        val days = if (first == null) emptyList() else (minOf(first, ledger.today)..ledger.today).toList()

        Backup(
            dayStartsAtHour = settings.rolloverHour,
            currency = settings.currency,
            goal = settings.goal,
            projectedStop = ledger.projection(settings.goal).stoppable?.toString(),
            drinks = rows.drinksByName().map {
                Backup.DrinkRecord(it.id, it.name, it.category, it.abv, it.vessel, it.volumeMl, it.price, it.isGeneric, it.isHidden)
            },
            favourites = rows.favouritesInOrder().map { Backup.FavouriteRecord(it.drinkId, it.vessel, it.volumeMl, it.price, it.sortOrder) },
            days = days.reversed().map { day ->
                val totals = ledger.totals(day)
                val status = when (ledger.status(day)) {
                    DayStatus.DRANK -> "drank"
                    DayStatus.ALCOHOL_FREE -> "alcohol_free"
                    DayStatus.TODAY -> "in_progress"
                    else -> "not_logged"
                }
                Backup.DayRecord(
                    date = day.toString(),
                    status = status,
                    units = totals.units.rounded2,
                    kcal = totals.kcal.rounded,
                    cost = totals.cost.rounded2,
                    spentByHand = ledger.spendOverride(day)?.rounded2,
                    budget = ledger.dailyBudget(day, settings.goal)?.rounded2,
                    pours = (byDay[day.number] ?: emptyList()).map {
                        Backup.PourRecord(it.id, it.timestamp, it.name, it.category, it.vessel, it.volumeMl, it.abv, it.units.rounded2, it.kcal.rounded, it.price, it.drink.id)
                    },
                )
            },
        )
    }

    /** UTF-8 JSON, laid out exactly as iOS lays it out. */
    fun json(backup: Backup): ByteArray = SwiftJson.encode(json.encodeToJsonElement(Backup.serializer(), backup)).toByteArray()

    fun decode(data: ByteArray): Backup = json.decodeFromString(Backup.serializer(), data.decodeToString())

    /** `groglog-2026-10-12.json`, dated by the drinking day. */
    fun fileName(kind: Kind, settings: Settings) = "groglog-${settings.clock.today}.${kind.extension}"

    /** A compact, readable log meant for pasting into a chat with an LLM. */
    fun markdown(backup: Backup, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        val money = { value: Double? -> (value ?: 0.0).money(backup.currency ?: "GBP") }
        val dateTime = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(locale).withZone(zone)
        val date = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).withZone(zone)
        val time = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).withZone(zone)
        val lines = mutableListOf(
            "# Drinking log",
            "",
            "Exported ${dateTime.format(backup.exportedAt ?: Instant.now())}. ${backup.notes ?: ""}",
            "",
        )
        val goal = backup.goal
        if (goal != null && goal.isEnabled) {
            val from = "from ${goal.baselineWeekly.unitsText} units/week starting ${date.format(goal.start)}"
            lines += when (goal.taper) {
                Taper.DYNAMIC -> "Goal: stepped taper, cut 10% every 4 days above 25 units/day, every 3 days above 15, then every day, compounding daily, down to ${goal.targetWeekly.unitsText} units/week, on a fixed schedule $from."
                Taper.PROPORTIONAL -> "Goal: cut ${goal.reductionPercent.toInt()}% every ${goal.periodDays} day(s), compounding daily, down to ${goal.targetWeekly.unitsText} units/week, on a fixed schedule $from."
                Taper.LINEAR -> "Goal: cut ${goal.reductionUnits.unitsText} units/day off the daily budget every ${goal.periodDays} day(s), down to ${goal.targetWeekly.unitsText} units/week, on a fixed schedule $from."
            }
            backup.projectedStop?.let { lines += "At this rate: down to ${Goal.STOP_FROM.unitsText} units/week, low enough to stop, by $it." }
            lines += ""
        }
        lines += listOf("## Days (newest first)", "")
        for (day in backup.days) {
            when (day.status) {
                "alcohol_free" -> lines += "- ${day.date}: alcohol-free"
                "not_logged" -> lines += "- ${day.date}: not logged"
                else -> {
                    val budget = day.budget?.let { " (budget ${it.unitsText})" } ?: ""
                    val soFar = if (day.status == "in_progress") " (so far)" else ""
                    lines += "- ${day.date}: ${(day.units ?: 0.0).unitsText} u$budget, ${(day.kcal ?: 0.0).toInt()} kcal, ${money(day.cost)}$soFar"
                    for (pour in day.pours ?: emptyList()) {
                        val at = pour.time?.let(time::format) ?: ""
                        lines += "  - $at ${pour.name}, ${(pour.volumeMl ?: 0.0).volumeText} at ${(pour.abv ?: 0.0).abvText}: ${(pour.units ?: 0.0).unitsText} u"
                    }
                }
            }
        }
        return lines.joinToString("\n")
    }

    /**
     * Merges a backup in one transaction without modifying existing data: drinks and entries are matched by id, and a
     * day that already has drinks keeps them. Settings present in the file are restored first, so entries land on the
     * correct days. Totals are recomputed for only the touched days. Returns how many entries were added.
     */
    suspend fun restore(data: ByteArray, database: AppDatabase, prefs: Prefs): Int {
        val backup = decode(data)
        // An hour outside 0-23 would break every date the clock builds, so the file is refused.
        backup.dayStartsAtHour?.let { if (it !in 0..23) throw ImportException.dayEndsAtImpossibleHour(it) }
        val before = prefs.current()
        val movesDayEnd = backup.dayStartsAtHour?.let { it != before.rolloverHour } ?: false
        backup.dayStartsAtHour?.let { prefs.setRolloverHour(it) }
        backup.currency?.let { prefs.setCurrency(it) }
        backup.goal?.let { prefs.setGoal(it) }
        val logbook = Logbook(database, prefs.current().clock)
        val clock = logbook.clock
        var added = 0

        logbook.bulk { rows ->
            // Backup drinks match existing ones by id, or by name and type (a fresh install's generics), so restoring
            // onto a new device does not duplicate every drink.
            val drinkIds = HashMap<UUID, UUID>()
            for (record in backup.drinks ?: emptyList()) {
                val existing = rows.drink(record.id) ?: rows.drink(record.name, record.category.raw)
                if (existing != null) {
                    drinkIds[record.id] = existing.id
                } else {
                    rows.insert(Drink(record.id, record.name, record.category, record.abv, record.vessel, record.volumeMl, record.price, record.isGeneric, record.isHidden))
                    drinkIds[record.id] = record.id
                }
            }
            for (record in backup.favourites ?: emptyList()) {
                val drinkId = drinkIds[record.drinkID] ?: continue
                if (rows.favourite(drinkId, record.vessel.raw, record.volumeMl) == null) {
                    rows.insert(Favourite(drinkId = drinkId, vessel = record.vessel, volumeMl = record.volumeMl, price = record.price, sortOrder = record.order))
                }
            }

            val existingPours = rows.pourIds().toSet()
            val daysWithPours = rows.daysWithPours().toSet()
            val touched = mutableSetOf<DayKey>()
            for (record in backup.days) {
                // A future day cannot have been drunk on, and would put the log's first day after today.
                val day = DayKey.parse(record.date) ?: continue
                if (day > clock.today || day.number in daysWithPours) continue
                if (record.status == "alcohol_free") {
                    rows.save((rows.day(day.number) ?: Day(day.number)).copy(isAlcoholFree = true))
                }
                record.spentByHand?.let { spent ->
                    rows.save((rows.day(day.number) ?: Day(day.number)).copy(costOverride = spent))
                    touched += day
                }
                val evening = clock.suggestedTime(day, null)
                val pours = record.pours ?: emptyList()
                val units = record.units
                if (pours.isEmpty() && units != null && units > 0) {
                    val drink = logbook.unitsDrink()
                    rows.insert(Pour(drinkId = drink.id, timestamp = evening, day = day.number, vessel = Vessel.SHOT, volumeMl = units * 10, price = record.cost ?: 0.0, kcalOverride = record.kcal))
                    added += 1
                    touched += day
                }
                pours.forEachIndexed { index, pour ->
                    if (pour.id != null && pour.id in existingPours) return@forEachIndexed
                    val time = pour.time ?: evening.plusSeconds(index * 30L * 60)
                    val id = pour.id ?: UUID.randomUUID()
                    val volume = pour.volumeMl
                    if (volume != null) {
                        val category = pour.category ?: DrinkCategory.BEER
                        val vessel = pour.vessel ?: category.defaultVessel
                        val drink = pour.drinkID?.let { drinkIds[it] }?.let { rows.drink(it) }
                            ?: logbook.findOrCreate(pour.name, category, pour.abv ?: category.defaultABV, vessel, volume)
                        val kcal = if (drink.category == DrinkCategory.UNITS) pour.kcal else null
                        val abv = pour.abv?.takeIf { it != drink.abv }
                        rows.insert(Pour(id, drink.id, time, day.number, vessel, volume, pour.price ?: 0.0, kcal, abv))
                    } else {
                        val drink = logbook.unitsDrink()
                        rows.insert(Pour(id, drink.id, time, day.number, Vessel.SHOT, (pour.units ?: 0.0) * 10, pour.price ?: 0.0, pour.kcal))
                    }
                    added += 1
                    touched += day
                }
            }
            touched
        }
        // Existing entries were assigned days by the old hour and imported ones by the new one, so every day is
        // reassigned.
        if (movesDayEnd) logbook.rebuild(reassigningDays = true)
        return added
    }
}

/** Rounded as iOS rounds, half away from zero, on the exact binary value. */
private val Double.rounded: Double get() = BigDecimal(this).setScale(0, RoundingMode.HALF_UP).toDouble()

private val Double.rounded2: Double get() = (this * 100).rounded / 100
