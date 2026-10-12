package cc.blit.groglog.model

import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.chrono.IsoChronology
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.time.format.FormatStyle
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * Maps moments onto drinking days. A day runs from `rolloverHour` to `rolloverHour` the next morning, so the 1am pint
 * counts towards the night it belongs to. `zone` and `firstWeekday` (1 = Sunday … 7 = Saturday) stand in for iOS's
 * `Calendar`.
 */
data class DayClock(
    val rolloverHour: Int,
    val zone: ZoneId = ZoneId.systemDefault(),
    val firstWeekday: Int = localFirstWeekday(),
) {
    val today: DayKey get() = day(Instant.now())

    /** Decided on the wall clock, so it agrees with `start(of:)` on the nights the clocks change. */
    fun day(instant: Instant): DayKey {
        val hour = instant.atZone(zone).hour
        return DayKey.of(instant, zone) - if (hour < rolloverHour) 1 else 0
    }

    fun start(day: DayKey): Instant = LocalDateTime.of(day.localDate, java.time.LocalTime.of(rolloverHour, 0)).atZone(zone).toInstant()

    fun end(day: DayKey): Instant = start(day + 1)

    fun weekStart(day: DayKey): DayKey = day - (day.weekday - firstWeekday + 7) % 7

    fun hours(instant: Instant, day: DayKey): Double = Duration.between(start(day), instant).toMillis() / 3_600_000.0

    /** Places a clock time within the drinking day: 01:30 lands after midnight rather than before the day began. */
    fun resolve(time: Instant, day: DayKey): Instant {
        val parts = time.atZone(zone)
        val date = (if (parts.hour < rolloverHour) day + 1 else day).localDate
        return LocalDateTime.of(date, java.time.LocalTime.of(parts.hour, parts.minute)).atZone(zone).toInstant()
    }

    /** The current time for today; otherwise just after the last drink, or 8pm for an empty day. */
    fun suggestedTime(day: DayKey, after: Instant?): Instant {
        if (day == today) return Instant.now()
        if (after != null) return minOf(after.plusSeconds(20 * 60), end(day).minusSeconds(60))
        return LocalDateTime.of(day.localDate, java.time.LocalTime.of(20, 0)).atZone(zone).toInstant()
    }

    fun hourLabel(hours: Double, locale: Locale = Locale.getDefault()): String {
        val pattern = DateTimeFormatterBuilder.getLocalizedDateTimePattern(null, FormatStyle.SHORT, IsoChronology.INSTANCE, locale)
        val hourOnly = if (pattern.contains('H') || pattern.contains('k')) "HH" else "h a"
        val at = start(today).plusMillis((hours * 3_600_000).toLong())
        return DateTimeFormatter.ofPattern(hourOnly, locale).format(at.atZone(zone))
    }

    companion object {
        fun localFirstWeekday(locale: Locale = Locale.getDefault()): Int =
            WeekFields.of(locale).firstDayOfWeek.value % 7 + 1
    }
}

/**
 * `hours(_:into:)` over a screen's worth of drinks. A day's start is a calendar calculation, so this caches it per day
 * rather than computing it per drink.
 */
class HourCounter(private val clock: DayClock) {
    private val starts = HashMap<Int, Instant>()

    fun hours(instant: Instant, day: DayKey): Double {
        val start = starts.getOrPut(day.number) { clock.start(day) }
        return Duration.between(start, instant).toMillis() / 3_600_000.0
    }
}
