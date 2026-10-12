package cc.blit.groglog.model

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
    val asleep: Double get() = deep + core + rem + unstaged

    /** Only for fully staged nights, since unstaged sleep would read as no REM. */
    val remShare: Double? get() = if (unstaged == 0.0 && asleep > 0) rem / asleep else null
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

data class Nights(val byDay: Map<DayKey, Night> = emptyMap()) {
    operator fun get(day: DayKey): Night? = byDay[day]

    val isEmpty: Boolean get() = byDay.isEmpty()

    val first: DayKey? get() = byDay.keys.minOrNull()

    /** The latest night before this one with a reading, however long ago. */
    fun last(reading: (Night) -> Double?, before: DayKey): DayKey? =
        byDay.filter { it.key < before && reading(it.value) != null }.keys.maxOrNull()

    /** The mean over a range of nights, or null if fewer than `minimum` have a reading. */
    fun mean(reading: (Night) -> Double?, days: DayRange, minimum: Int = 3): Double? {
        val values = days.mapNotNull { byDay[it]?.let(reading) }
        return if (values.size >= minimum) values.mean else null
    }

    companion object {
        /**
         * Files readings under the night they followed. HRV is taken only overnight, since a daytime spot reading
         * reflects the day's activity, and a night with several readings uses their mean. Sleep is filed by when it
         * began, so a bedtime after midnight counts for the evening before. Sleeping rate uses only beats inside an
         * asleep stage.
         */
        fun of(
            hrv: List<Pair<Instant, Double>> = emptyList(),
            restingHR: List<Pair<Instant, Double>> = emptyList(),
            sleep: List<SleepSpan> = emptyList(),
            heartRate: List<Pair<Instant, Double>> = emptyList(),
            clock: DayClock,
        ): Nights {
            val byDay = LinkedHashMap<DayKey, Night>()
            fun edit(day: DayKey, change: (Night) -> Night) {
                byDay[day] = change(byDay[day] ?: Night())
            }
            for ((day, values) in hrv.filter { clock.isOvernight(it.first) }.groupBy { clock.night(it.first) }) {
                edit(day) { it.copy(hrv = values.map { v -> v.second }.mean) }
            }
            for ((day, values) in restingHR.groupBy { clock.night(it.first) }) {
                edit(day) { it.copy(restingHR = values.map { v -> v.second }.mean) }
            }
            val asleep = mutableListOf<TimeSpan>()
            for ((day, spans) in sleepByNight(sleep, clock)) {
                var night = Sleep()
                for (span in spans) {
                    val seconds = span.span.seconds
                    night = when (span.stage) {
                        SleepStage.DEEP -> night.copy(deep = night.deep + seconds)
                        SleepStage.CORE -> night.copy(core = night.core + seconds)
                        SleepStage.REM -> night.copy(rem = night.rem + seconds)
                        SleepStage.UNSTAGED -> night.copy(unstaged = night.unstaged + seconds)
                        SleepStage.AWAKE -> night.copy(awake = night.awake + seconds)
                    }
                }
                edit(day) { it.copy(sleep = night) }
                asleep += spans.filter { it.stage != SleepStage.AWAKE }.map { it.span }
            }
            asleep.sortBy { it.start }
            val sleeping = LinkedHashMap<DayKey, MutableList<Double>>()
            var i = 0
            for ((instant, value) in heartRate.sortedBy { it.first }) {
                while (i < asleep.size && asleep[i].end <= instant) i += 1
                if (i >= asleep.size || instant !in asleep[i]) continue
                sleeping.getOrPut(clock.night(asleep[i].start)) { mutableListOf() } += value
            }
            for ((day, values) in sleeping) edit(day) { it.copy(sleepingHR = values.mean) }
            return Nights(byDay)
        }

        /** Each night's spans from the one device that recorded the most sleep that night. */
        fun sleepByNight(spans: List<SleepSpan>, clock: DayClock): Map<DayKey, List<SleepSpan>> =
            spans.groupBy { clock.night(it.span.start) }.mapValues { (_, spans) ->
                spans.groupBy { it.source }.values.maxBy { source ->
                    source.filter { it.stage != SleepStage.AWAKE }.sumOf { it.span.seconds }
                }
            }

        /** Each night's first sleep to its last, one span per night, for fetching the heart rate inside them. */
        fun nightSpans(spans: List<SleepSpan>, clock: DayClock): List<TimeSpan> =
            sleepByNight(spans, clock).values.map { night ->
                val asleep = night.filter { it.stage != SleepStage.AWAKE }.map { it.span }
                TimeSpan(asleep.minOfOrNull { it.start } ?: night[0].span.start, asleep.maxOfOrNull { it.end } ?: night[0].span.end)
            }
    }
}

/**
 * The drinking day a reading belongs to. With a 5am day end a night runs 8pm to 8pm, so the 11pm reading, the 3am one
 * and the resting rate stamped on the next morning all belong to the preceding evening.
 */
fun DayClock.night(instant: Instant): DayKey = day(instant.minusSeconds(15 * 3600))

/** 8pm to noon, on a 5am day end. */
fun DayClock.isOvernight(instant: Instant): Boolean {
    val shifted = instant.minusSeconds(15 * 3600)
    return hours(shifted, day(shifted)) < 16
}

val List<Double>.mean: Double? get() = if (isEmpty()) null else sum() / size
