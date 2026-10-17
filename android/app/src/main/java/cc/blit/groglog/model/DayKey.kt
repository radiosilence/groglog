package cc.blit.groglog.model

import cc.blit.groglog.core.dayParse
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * A calendar date with no time or zone, identifying a drinking day. Held as days since 1970-01-01 so day arithmetic
 * is integer arithmetic, and so a night logged in one timezone stays on its date in another.
 */
@Serializable(with = DayKeySerializer::class)
@JvmInline
value class DayKey(val number: Int) : Comparable<DayKey> {

    data class Components(val year: Int, val month: Int, val day: Int)

    val components: Components
        get() {
            val z = number + 719_468
            val era = (if (z >= 0) z else z - 146_096) / 146_097
            val doe = z - era * 146_097
            val yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
            val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
            val mp = (5 * doy + 2) / 153
            val day = doy - (153 * mp + 2) / 5 + 1
            val month = if (mp < 10) mp + 3 else mp - 9
            return Components(yoe + era * 400 + if (month <= 2) 1 else 0, month, day)
        }

    /** 1 = Sunday … 7 = Saturday, matching iOS's `Calendar`. */
    val weekday: Int get() = ((number + 4) % 7 + 7) % 7 + 1

    val monthStart: DayKey
        get() {
            val c = components
            return of(c.year, c.month, 1)
        }

    val daysInMonth: Int
        get() {
            val c = components
            val next = if (c.month == 12) of(c.year + 1, 1, 1) else of(c.year, c.month + 1, 1)
            return monthStart.distanceTo(next)
        }

    /** Local midnight, for display and chart axes. */
    fun date(zone: ZoneId): Instant = localDate.atStartOfDay(zone).toInstant()

    val localDate: LocalDate get() = components.let { LocalDate.of(it.year, it.month, it.day) }

    operator fun plus(n: Int) = DayKey(number + n)
    operator fun minus(n: Int) = DayKey(number - n)
    fun distanceTo(other: DayKey) = other.number - number
    operator fun rangeTo(other: DayKey) = DayRange(this, other)
    override fun compareTo(other: DayKey) = number.compareTo(other.number)

    /** `yyyy-MM-dd`. */
    override fun toString(): String {
        val c = components
        return String.format(Locale.ROOT, "%04d-%02d-%02d", c.year, c.month, c.day)
    }

    companion object {
        /** Days from civil date (Howard Hinnant's algorithm), valid for the proleptic Gregorian calendar. Kept in Kotlin because
         * it runs per row and a call into the core costs microseconds; `CoreParityTests` holds it to the core's. */
        fun of(year: Int, month: Int, day: Int): DayKey {
            val y = if (month <= 2) year - 1 else year
            val era = (if (y >= 0) y else y - 399) / 400
            val yoe = y - era * 400
            val doy = (153 * (month + if (month > 2) -3 else 9) + 2) / 5 + day - 1
            val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            return DayKey(era * 146_097 + doe - 719_468)
        }

        /** The civil date `instant` falls on in `zone`. */
        fun of(instant: Instant, zone: ZoneId): DayKey {
            val date = instant.atZone(zone).toLocalDate()
            return of(date.year, date.monthValue, date.dayOfMonth)
        }

        /**
         * A valid `yyyy-MM-dd` date. Imported files are parsed with this, so impossible or day-first dates are refused
         * rather than rolled over into another day.
         */
        fun parse(string: String): DayKey? = dayParse(string)?.let { DayKey(it.toInt()) }
    }
}

/** An inclusive run of days that can be iterated, like Swift's `ClosedRange<DayKey>`. */
data class DayRange(override val start: DayKey, override val endInclusive: DayKey) : ClosedRange<DayKey>, Iterable<DayKey> {
    override fun iterator(): Iterator<DayKey> = (start.number..endInclusive.number).asSequence().map(::DayKey).iterator()
    val count: Int get() = maxOf(0, endInclusive.number - start.number + 1)
}

object DayKeySerializer : KSerializer<DayKey> {
    override val descriptor = PrimitiveSerialDescriptor("cc.blit.groglog.DayKey", PrimitiveKind.STRING)
    override fun serialize(encoder: Encoder, value: DayKey) = encoder.encodeString(value.toString())
    override fun deserialize(decoder: Decoder): DayKey {
        val string = decoder.decodeString()
        return DayKey.parse(string) ?: throw SerializationException("Expected yyyy-MM-dd, got $string")
    }
}
