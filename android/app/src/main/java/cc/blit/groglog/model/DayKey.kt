package cc.blit.groglog.model

import cc.blit.groglog.core.dayCivil
import cc.blit.groglog.core.dayDaysInMonth
import cc.blit.groglog.core.dayFormat
import cc.blit.groglog.core.dayMonthStart
import cc.blit.groglog.core.dayNumber
import cc.blit.groglog.core.dayParse
import cc.blit.groglog.core.dayWeekday
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
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
        get() = dayCivil(number.toLong()).let { Components(it.year.toInt(), it.month.toInt(), it.day.toInt()) }

    /** 1 = Sunday … 7 = Saturday, matching iOS's `Calendar`. */
    val weekday: Int get() = dayWeekday(number.toLong()).toInt()

    val monthStart: DayKey get() = DayKey(dayMonthStart(number.toLong()).toInt())

    val daysInMonth: Int get() = dayDaysInMonth(number.toLong()).toInt()

    /** Local midnight, for display and chart axes. */
    fun date(zone: ZoneId): Instant = localDate.atStartOfDay(zone).toInstant()

    val localDate: LocalDate get() = components.let { LocalDate.of(it.year, it.month, it.day) }

    operator fun plus(n: Int) = DayKey(number + n)
    operator fun minus(n: Int) = DayKey(number - n)
    fun distanceTo(other: DayKey) = other.number - number
    operator fun rangeTo(other: DayKey) = DayRange(this, other)
    override fun compareTo(other: DayKey) = number.compareTo(other.number)

    /** `yyyy-MM-dd`. */
    override fun toString(): String = dayFormat(number.toLong())

    companion object {
        /** Days from civil date, in the proleptic Gregorian calendar. */
        fun of(year: Int, month: Int, day: Int): DayKey = DayKey(dayNumber(year.toLong(), month.toLong(), day.toLong()).toInt())

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
