package cc.blit.groglog.model

import cc.blit.groglog.core.CoreNights
import cc.blit.groglog.core.NightRow
import cc.blit.groglog.core.ReadingIn
import cc.blit.groglog.core.ReadingKind
import cc.blit.groglog.core.SampleIn
import cc.blit.groglog.core.SleepIn
import cc.blit.groglog.core.SleepRow
import cc.blit.groglog.core.StageKind
import cc.blit.groglog.core.nightsBuild
import cc.blit.groglog.core.nightsIsOvernight
import cc.blit.groglog.core.nightsNightSpans
import cc.blit.groglog.core.nightsShiftHours
import cc.blit.groglog.core.sleepAsleep
import cc.blit.groglog.core.sleepRemShare
import java.time.Duration
import java.time.Instant

/**
 * Body readings after a drinking day: overnight HRV in ms, and resting and sleeping heart rate in bpm, from whatever
 * records them. A night with no reading is null and is excluded from every average.
 */
data class Night(
    val hrv: Double? = null,
    val restingHR: Double? = null,
    /** The mean heart rate while asleep. Closer to the night than resting rate, which a watch derives over a whole day. */
    val sleepingHR: Double? = null,
    val sleep: Sleep? = null,
)

/** A night's sleep by stage, in seconds. */
data class Sleep(
    val deep: Double = 0.0,
    val core: Double = 0.0,
    val rem: Double = 0.0,
    /** Asleep with no stage given, as older watches record it. */
    val unstaged: Double = 0.0,
    val awake: Double = 0.0,
) {
    val asleep: Double get() = sleepAsleep(row)

    /** Only for fully staged nights, since unstaged sleep would read as no REM. */
    val remShare: Double? get() = sleepRemShare(row)

    private val row get() = SleepRow(deep, core, rem, unstaged, awake)
}

enum class SleepStage { AWAKE, CORE, DEEP, REM, UNSTAGED }

/** A span of time, closed at both ends as iOS's `DateInterval` is. */
data class TimeSpan(val start: Instant, val end: Instant) {
    val seconds: Double get() = Duration.between(start, end).toMillis() / 1000.0
    operator fun contains(instant: Instant) = instant >= start && instant <= end
}

data class SleepSpan(
    val span: TimeSpan,
    val stage: SleepStage,
    /** The recording device. Two devices recording the same night would double it, so only one is used. */
    val source: String,
)

class Nights(val byDay: Map<DayKey, Night> = emptyMap()) {
    private val core = CoreNights(
        byDay.map { (day, night) ->
            NightRow(
                day.number.toLong(), night.hrv, night.restingHR, night.sleepingHR,
                night.sleep?.let { SleepRow(it.deep, it.core, it.rem, it.unstaged, it.awake) },
            )
        },
    )

    override fun equals(other: Any?) = other is Nights && other.byDay == byDay

    override fun hashCode() = byDay.hashCode()

    operator fun get(day: DayKey): Night? = byDay[day]

    val isEmpty: Boolean get() = byDay.isEmpty()

    val first: DayKey? get() = core.first()?.let { DayKey(it.toInt()) }

    /** The latest night before this one with a reading, however long ago. */
    fun last(reading: (Night) -> Double?, before: DayKey): DayKey? =
        core.last(kind(reading), before.number.toLong())?.let { DayKey(it.toInt()) }

    /** The mean over a range of nights, or null if fewer than `minimum` have a reading. */
    fun mean(reading: (Night) -> Double?, days: DayRange, minimum: Int = 3): Double? =
        core.mean(kind(reading), days.start.number.toLong(), days.endInclusive.number.toLong(), minimum.toLong())

    /** Which reading a selector picks: the probe has only that one set. */
    private fun kind(reading: (Night) -> Double?): ReadingKind = when {
        reading(Night(hrv = 1.0)) != null -> ReadingKind.HRV
        reading(Night(restingHR = 1.0)) != null -> ReadingKind.RESTING_HR
        else -> ReadingKind.SLEEPING_HR
    }

    companion object {
        /**
         * Files readings under the night they followed. HRV is taken only overnight, since a daytime spot reading
         * reflects the day's activity, and a night with several readings uses their mean. Sleep is filed by when it
         * began, so a bedtime after midnight counts for the evening before. Sleeping rate uses only beats inside an
         * asleep stage. Which night a moment belongs to is the calendar's to say; the filing is the shared core's.
         */
        fun of(
            hrv: List<Pair<Instant, Double>> = emptyList(),
            restingHR: List<Pair<Instant, Double>> = emptyList(),
            sleep: List<SleepSpan> = emptyList(),
            heartRate: List<Pair<Instant, Double>> = emptyList(),
            clock: DayClock,
        ): Nights {
            val rows = nightsBuild(
                hrv.filter { clock.isOvernight(it.first) }.map { ReadingIn(clock.night(it.first).number.toLong(), it.second) },
                restingHR.map { ReadingIn(clock.night(it.first).number.toLong(), it.second) },
                sleep.map { sleepIn(it, clock) },
                heartRate.map { SampleIn(seconds(it.first), it.second) },
            )
            return Nights(
                rows.associate { row ->
                    DayKey(row.day.toInt()) to Night(
                        row.hrv, row.restingHr, row.sleepingHr,
                        row.sleep?.let { Sleep(it.deep, it.core, it.rem, it.unstaged, it.awake) },
                    )
                },
            )
        }

        /** Each night's first sleep to its last, one span per night, for fetching the heart rate inside them. */
        fun nightSpans(spans: List<SleepSpan>, clock: DayClock): List<TimeSpan> =
            nightsNightSpans(spans.map { sleepIn(it, clock) }).map { TimeSpan(instant(it.start), instant(it.end)) }

        private fun sleepIn(span: SleepSpan, clock: DayClock) = SleepIn(
            clock.night(span.span.start).number.toLong(),
            seconds(span.span.start),
            seconds(span.span.end),
            when (span.stage) {
                SleepStage.AWAKE -> StageKind.AWAKE
                SleepStage.CORE -> StageKind.CORE
                SleepStage.DEEP -> StageKind.DEEP
                SleepStage.REM -> StageKind.REM
                SleepStage.UNSTAGED -> StageKind.UNSTAGED
            },
            span.source,
        )

        private fun seconds(instant: Instant) = instant.toEpochMilli() / 1000.0

        private fun instant(seconds: Double) = Instant.ofEpochMilli(Math.round(seconds * 1000))
    }
}

/**
 * The drinking day a reading belongs to. With a 5am day end a night runs 8pm to 8pm, so the 11pm reading, the 3am one
 * and the resting rate stamped on the next morning all belong to the preceding evening.
 */
fun DayClock.night(instant: Instant): DayKey = day(instant.minusMillis((nightsShiftHours() * 3_600_000).toLong()))

/** 8pm to noon, on a 5am day end. */
fun DayClock.isOvernight(instant: Instant): Boolean {
    val shifted = instant.minusMillis((nightsShiftHours() * 3_600_000).toLong())
    return nightsIsOvernight(hours(shifted, day(shifted)))
}

val List<Double>.mean: Double? get() = if (isEmpty()) null else sum() / size
