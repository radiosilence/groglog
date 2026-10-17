package cc.blit.groglog.model

import cc.blit.groglog.core.GoalSpec
import cc.blit.groglog.core.TaperKind
import cc.blit.groglog.core.goalDailyCut
import cc.blit.groglog.core.goalDailyUnitCut
import cc.blit.groglog.core.goalIsFasterThanSafe
import cc.blit.groglog.core.goalNearestOfferedPeriod
import cc.blit.groglog.core.goalNearestOfferedUnits
import cc.blit.groglog.core.goalNearestPeriodToDailyCut
import cc.blit.groglog.core.goalOpeningDrop
import cc.blit.groglog.core.goalPaceDrinking
import cc.blit.groglog.core.goalPeriodsFrom
import cc.blit.groglog.core.goalRateForPace
import cc.blit.groglog.core.goalSharpensBelow
import cc.blit.groglog.core.goalSharpensWhileItMatters
import cc.blit.groglog.core.goalUnitCuts
import java.time.Instant
import kotlin.math.abs
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** How the budget comes down. */
@Serializable
enum class Taper(val raw: String) {
    /**
     * Ten per cent at a time off a fixed baseline, at the quickest pace the guidance allows for the current budget, so
     * it quickens as it falls. Shown as "Stepped"; the raw value is persisted, so the case keeps its original name.
     */
    @SerialName("dynamic") DYNAMIC("dynamic"),

    /** A share off a fixed baseline. Steep at first, shallow later, and never reaches zero. */
    @SerialName("proportional") PROPORTIONAL("proportional"),

    /**
     * The same number of units off every period. Reaches zero on a fixed date, but the share it takes grows as the
     * budget shrinks, so the last stretch is the sharpest.
     */
    @SerialName("linear") LINEAR("linear");

    val label: String
        get() = when (this) {
            DYNAMIC -> "Stepped"
            PROPORTIONAL -> "Proportional"
            LINEAR -> "Linear"
        }

    /** A one-line description, since the names alone do not explain the behaviour. */
    val explanation: String
        get() = when (this) {
            DYNAMIC -> "Begins at the fastest pace the guidance allows for your current intake, and quickens each time the budget passes a threshold. Progress is slowest at the highest levels."
            PROPORTIONAL -> "Removes the same percentage each time. It falls quickly at first and more gently as it goes, approaching zero without reaching it."
            LINEAR -> "Removes the same number of units each time and reaches zero on a fixed date. Each cut becomes a larger share of what remains."
        }

    companion object {
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw }
    }
}

/** A choice of pace: how many days apart the cut lands, and how the picker names it. */
data class Period(val days: Int, val label: String)

/**
 * Brings the budget down until it reaches `targetWeekly`. A proportional taper cuts `reductionPercent` every
 * `periodDays`, compounded smoothly day by day so the budget never steps. A linear taper takes `reductionUnits` off the
 * daily budget over the same period. Dynamic (Stepped) is proportional with the period taken from `ladder` rather than
 * chosen. The maths lives in `Ledger`.
 */
@Serializable(with = GoalSerializer::class)
data class Goal(
    val isEnabled: Boolean = false,
    val taper: Taper = Taper.DYNAMIC,
    val baselineWeekly: Double = 28.0,
    val reductionPercent: Double = STANDARD_CUT,
    /** How much a linear taper takes off the daily budget each period, in units a day. */
    val reductionUnits: Double = 1.0,
    /**
     * Ten per cent every four days to begin with, about 2.6% a day. Ten per cent a day is the safe ceiling, not a
     * suitable starting pace.
     */
    val periodDays: Int = 4,
    val start: Instant = Instant.now(),
    /**
     * Zero rather than the guideline: most people setting a goal are aiming for none, and an unrequested floor would
     * stop the budget coming down.
     */
    val targetWeekly: Double = 0.0,
) {
    /**
     * What this takes off the budget on its first day: the steepest step of a proportional taper, and every step of a
     * linear one.
     */
    fun openingDrop(weekly: Double): Double = goalOpeningDrop(spec(), weekly)

    /** The equivalent share per day, for comparing proportional plans on the same footing. */
    val dailyCut: Double get() = goalDailyCut(spec())

    /** Units off the daily budget per day, for a linear plan. */
    val dailyUnitCut: Double get() = goalDailyUnitCut(spec())

    /**
     * A linear taper takes the same units off whatever the budget, so the share it takes climbs as the budget falls: it
     * passes the safe rate at this daily budget and is sharper than it from there down.
     */
    val sharpensBelow: Double get() = goalSharpensBelow(spec())

    /**
     * Whether to warn about it. The 10%-a-day limit concerns withdrawal from heavy drinking and has no meaning near the
     * guideline, where warning would contradict the advice on the same screen. The warning applies only when the taper
     * sharpens while intake is still high.
     */
    fun sharpensWhileItMatters(weekly: Double) = goalSharpensWhileItMatters(spec(), weekly)

    val isFasterThanSafe: Boolean get() = goalIsFasterThanSafe(spec())

    /**
     * The goal as the shared maths sees it. `startDay` is the day the taper begins, which depends on the zone the start
     * time is read in; the figures that do not involve a date leave it at zero.
     */
    fun spec(startDay: DayKey = DayKey(0)) = GoalSpec(
        isEnabled,
        when (taper) {
            Taper.DYNAMIC -> TaperKind.DYNAMIC
            Taper.PROPORTIONAL -> TaperKind.PROPORTIONAL
            Taper.LINEAR -> TaperKind.LINEAR
        },
        baselineWeekly,
        reductionPercent,
        reductionUnits,
        periodDays.toLong(),
        startDay.number.toLong(),
        targetWeekly,
    )

    companion object {
        /**
         * Ten per cent a day is the ceiling in the DHSC's UK clinical guidelines for alcohol treatment (chapter 8, harm
         * reduction, November 2025), the first national guideline to quantify reducing without medication. The text
         * calls the figure clinical consensus rather than trial evidence, and the protocol assumes a clinician has
         * judged the person suitable and reviews them throughout. An app can do neither, so nothing here presents a
         * plan as advice.
         */
        const val SAFE_DAILY_CUT = 0.10

        /**
         * Same guidance: above this, over 65, or in poor health, a person may need to go slower, at no more than 10%
         * every four days. A new goal starts at that pace.
         */
        const val SLOWER_ABOVE_WEEKLY = 25 * 7.0

        /** NICE CG115 recommendation 1.3.4.1: over 15 units a day, consider assisted withdrawal. */
        const val ASSISTED_WITHDRAWAL_WEEKLY = 15 * 7.0

        /**
         * The level below which a taper can end. A proportional taper never reaches zero, so a plan aimed at zero would
         * have a tail months long. Alcohol services put the point at which a person can simply stop at around ten
         * units a day, below NICE's threshold for assisted withdrawal. This figure is not in the written guidance.
         */
        const val STOP_FROM = 10 * 7.0

        /** NICE CG115 recommendation 1.3.4.5: over 30 units a day, consider inpatient or residential. */
        const val INPATIENT_WEEKLY = 30 * 7.0

        /**
         * The share cut each period. It is fixed at the safe ceiling, so pace is set only by how often the cut lands:
         * 10% a day at one day apart, about 1.5% a day at a week. No option can then be set too fast, which a menu of
         * shares would allow.
         */
        const val STANDARD_CUT = 10.0

        val periods: List<Period> = listOf(Period(1, "day"), Period(3, "3 days"), Period(4, "4 days"), Period(7, "week"))

        /**
         * What a linear taper can take off the daily budget each period. Two units is the maximum: at a day apart it
         * empties a heavy drinker's budget within a fortnight, and below 20 units a day it already exceeds the 10%
         * ceiling.
         */
        val unitCuts: List<Double> = listOf(0.5, 1.0, 1.5, 2.0)

        /**
         * `weekly` is the taper's baseline, which decides the size of its steps. Over 25 units a day the guidance sets
         * a slower pace of no more than 10% every four days, so the two quicker periods are not offered.
         */
        fun periods(weekly: Double): List<Period> = goalPeriodsFrom(weekly).mapNotNull { days -> periods.firstOrNull { it.days.toLong() == days } }

        /**
         * The pace to fall back on when a baseline change removes the chosen one: the quickest still offered, so
         * raising the baseline slows the taper as little as possible.
         */
        fun nearestOffered(period: Int, weekly: Double): Int = goalNearestOfferedPeriod(period.toLong(), weekly).toInt()

        fun nearestOffered(units: Double, weekly: Double, perDays: Int): Double = goalNearestOfferedUnits(units, weekly, perDays.toLong())

        /**
         * The pace a dynamic taper runs at once the budget reaches this level: the quickest offered there, taken from
         * the same list as the picker so the two cannot disagree.
         */
        fun pace(weekly: Double): Int = goalPaceDrinking(weekly).toInt()

        /**
         * The linear amounts offered. A share scales with intake but a fixed number of units does not: two a day off a
         * ten-a-day budget is 20%, twice the ceiling, on the first day. Only amounts that open inside the ceiling are
         * offered; where none do, the smallest is kept so the picker is never empty.
         */
        fun unitCuts(weekly: Double, perDays: Int): List<Double> = goalUnitCuts(weekly, perDays.toLong())

        /**
         * The offered period closest in pace to a rate, for a goal saved with a period no longer offered. The daily
         * rate is matched rather than the number of days, which could make a long taper several times faster.
         */
        fun nearestPeriod(dailyCut: Double): Int = goalNearestPeriodToDailyCut(dailyCut).toInt()

        /** The daily rate a pace compounds to. */
        fun rate(pace: Int): Double = goalRateForPace(pace.toLong())
    }
}

/**
 * Reads and writes a goal as iOS does. Every field is optional with a default, so a goal saved by an older build keeps
 * the fields it set; a strict decoder would throw on a missing key and silently reset a taper in progress.
 */
object GoalSerializer : KSerializer<Goal> {
    override val descriptor = buildClassSerialDescriptor("cc.blit.groglog.Goal")

    /** Seconds from 1970 to 2001, the reference date iOS counts a bare-number date from. */
    private const val REFERENCE_DATE = 978_307_200L

    override fun serialize(encoder: Encoder, value: Goal) {
        (encoder as JsonEncoder).encodeJsonElement(encode(value))
    }

    override fun deserialize(decoder: Decoder): Goal = decode((decoder as JsonDecoder).decodeJsonElement().jsonObject)

    fun encode(goal: Goal) = buildJsonObject {
        put("isEnabled", goal.isEnabled)
        put("taper", goal.taper.raw)
        put("baselineWeekly", goal.baselineWeekly)
        put("reductionPercent", goal.reductionPercent)
        put("reductionUnits", goal.reductionUnits)
        put("periodDays", goal.periodDays)
        put("start", Iso8601.format(goal.start))
        put("targetWeekly", goal.targetWeekly)
    }

    fun decode(json: JsonObject): Goal {
        fun field(key: String) = json[key]?.takeIf { it !is JsonNull }?.jsonPrimitive
        // A quoted "true" or "4.5" is refused as iOS's JSONDecoder refuses it, rather than read as the value it
        // spells, so a file one platform rejects is rejected by both.
        fun bare(key: String) = field(key)?.also { if (it.isString) throw SerializationException("Expected a bare value for $key, got \"${it.content}\"") }
        val fallback = Goal()
        val start = field("start")?.let { value ->
            if (value.isString) Iso8601.parse(value.content) ?: throw SerializationException("Expected an ISO 8601 date, got ${value.content}")
            else Instant.ofEpochMilli(Math.round((value.double + REFERENCE_DATE) * 1000))
        }
        // Older builds stored the taper as a Bool choosing between dynamic and proportional.
        val taper = field("taper")?.let { Taper.fromRaw(it.content) ?: throw SerializationException("Unknown taper ${it.content}") }
            ?: bare("isDynamic")?.boolean?.let { if (it) Taper.DYNAMIC else Taper.PROPORTIONAL }
            ?: fallback.taper
        var goal = Goal(
            isEnabled = bare("isEnabled")?.boolean ?: fallback.isEnabled,
            taper = taper,
            baselineWeekly = bare("baselineWeekly")?.double ?: fallback.baselineWeekly,
            reductionPercent = bare("reductionPercent")?.double ?: fallback.reductionPercent,
            reductionUnits = bare("reductionUnits")?.double ?: fallback.reductionUnits,
            periodDays = bare("periodDays")?.int ?: fallback.periodDays,
            start = start ?: fallback.start,
            targetWeekly = bare("targetWeekly")?.double ?: fallback.targetWeekly,
        )
        // A share or period the picker no longer offers would leave it blank, so the goal moves to the offered value
        // nearest its existing pace.
        if (goal.reductionUnits !in Goal.unitCuts) {
            goal = goal.copy(reductionUnits = Goal.unitCuts.minByOrNull { abs(it - goal.reductionUnits) } ?: 1.0)
        }
        if (goal.reductionPercent != Goal.STANDARD_CUT || Goal.periods.none { it.days == goal.periodDays }) {
            goal = goal.copy(reductionPercent = Goal.STANDARD_CUT, periodDays = Goal.nearestPeriod(goal.dailyCut))
        }
        return goal
    }

    fun decode(string: String): Goal = decode(Json.parseToJsonElement(string).jsonObject)
}
