package cc.blit.groglog.model

import java.time.Instant
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.pow
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

/** A rung of the stepped taper: above this weekly level, the quickest pace offered. */
data class Rung(val aboveWeekly: Double, val pace: Int)

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
    fun openingDrop(weekly: Double): Double = when (taper) {
        Taper.LINEAR -> dailyUnitCut
        // Stepped starts on whichever rung its baseline lands it on.
        Taper.DYNAMIC -> weekly / 7 * rate(pace(weekly))
        Taper.PROPORTIONAL -> weekly / 7 * dailyCut
    }

    /** The equivalent share per day, for comparing proportional plans on the same footing. */
    val dailyCut: Double get() = 1 - (1 - reductionPercent / 100).pow(1 / max(1, periodDays).toDouble())

    /** Units off the daily budget per day, for a linear plan. */
    val dailyUnitCut: Double get() = reductionUnits / max(1, periodDays)

    /**
     * A linear taper takes the same units off whatever the budget, so the share it takes climbs as the budget falls: it
     * passes the safe rate at this daily budget and is sharper than it from there down.
     */
    val sharpensBelow: Double get() = dailyUnitCut / SAFE_DAILY_CUT

    /**
     * Whether to warn about it. The 10%-a-day limit concerns withdrawal from heavy drinking and has no meaning near the
     * guideline, where warning would contradict the advice on the same screen. The warning applies only when the taper
     * sharpens while intake is still high.
     */
    fun sharpensWhileItMatters(weekly: Double) =
        taper == Taper.LINEAR && weekly >= ASSISTED_WITHDRAWAL_WEEKLY && sharpensBelow > Units.WEEKLY_GUIDELINE / 7

    val isFasterThanSafe: Boolean
        get() = when (taper) {
            Taper.DYNAMIC, Taper.PROPORTIONAL -> dailyCut > SAFE_DAILY_CUT + 0.0005
            // Safe at the start and too fast at the end, so a single answer would be wrong; `sharpensBelow` gives the
            // crossover.
            Taper.LINEAR -> false
        }

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
         * The quickest pace offered above each level, used both to narrow the picker and as the rung a stepped taper
         * runs at. Over 25 units a day the guidance sets the limit. The rung below is this app's own: NICE considers
         * assisted withdrawal over 15 a day, and the ceiling was not written for unsupervised reduction at that level.
         * Under 15 the ceiling applies.
         */
        val ladder: List<Rung> = listOf(
            Rung(SLOWER_ABOVE_WEEKLY, 4),
            Rung(ASSISTED_WITHDRAWAL_WEEKLY, 3),
            Rung(Double.NEGATIVE_INFINITY, 1),
        )

        /**
         * `weekly` is the taper's baseline, which decides the size of its steps. Over 25 units a day the guidance sets
         * a slower pace of no more than 10% every four days, so the two quicker periods are not offered.
         */
        fun periods(weekly: Double): List<Period> {
            val floor = ladder.first { weekly > it.aboveWeekly }.pace
            val offered = periods.filter { it.days >= floor }
            return offered.ifEmpty { listOf(periods.last()) }
        }

        /**
         * The pace to fall back on when a baseline change removes the chosen one: the quickest still offered, so
         * raising the baseline slows the taper as little as possible.
         */
        fun nearestOffered(period: Int, weekly: Double): Int {
            val offered = periods(weekly).map { it.days }
            return if (period in offered) period else offered.minOrNull() ?: periods.last().days
        }

        fun nearestOffered(units: Double, weekly: Double, perDays: Int): Double {
            val offered = unitCuts(weekly, perDays)
            return if (units in offered) units else offered.maxOrNull() ?: unitCuts[0]
        }

        /**
         * The pace a dynamic taper runs at once the budget reaches this level: the quickest offered there, taken from
         * the same list as the picker so the two cannot disagree.
         */
        fun pace(weekly: Double): Int = periods(weekly).minOfOrNull { it.days } ?: periods.last().days

        /**
         * The linear amounts offered. A share scales with intake but a fixed number of units does not: two a day off a
         * ten-a-day budget is 20%, twice the ceiling, on the first day. Only amounts that open inside the ceiling are
         * offered; where none do, the smallest is kept so the picker is never empty.
         */
        fun unitCuts(weekly: Double, perDays: Int): List<Double> {
            val ceiling = weekly / 7 * SAFE_DAILY_CUT * max(1, perDays)
            val offered = unitCuts.filter { it <= ceiling + 0.0001 }
            return offered.ifEmpty { listOf(unitCuts.minOrNull() ?: 0.5) }
        }

        /**
         * The offered period closest in pace to a rate, for a goal saved with a period no longer offered. The daily
         * rate is matched rather than the number of days, which could make a long taper several times faster.
         */
        fun nearestPeriod(dailyCut: Double): Int =
            periods.map { it.days }.minByOrNull { abs(Goal(periodDays = it).dailyCut - dailyCut) } ?: 1

        /** The daily rate a pace compounds to. */
        fun rate(pace: Int): Double = 1 - (1 - STANDARD_CUT / 100).pow(1 / max(1, pace).toDouble())
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
        val fallback = Goal()
        val start = field("start")?.let { value ->
            if (value.isString) Iso8601.parse(value.content) ?: throw SerializationException("Expected an ISO 8601 date, got ${value.content}")
            else Instant.ofEpochMilli(Math.round((value.double + REFERENCE_DATE) * 1000))
        }
        // Older builds stored the taper as a Bool choosing between dynamic and proportional.
        val taper = field("taper")?.let { Taper.fromRaw(it.content) ?: throw SerializationException("Unknown taper ${it.content}") }
            ?: field("isDynamic")?.boolean?.let { if (it) Taper.DYNAMIC else Taper.PROPORTIONAL }
            ?: fallback.taper
        var goal = Goal(
            isEnabled = field("isEnabled")?.boolean ?: fallback.isEnabled,
            taper = taper,
            baselineWeekly = field("baselineWeekly")?.double ?: fallback.baselineWeekly,
            reductionPercent = field("reductionPercent")?.double ?: fallback.reductionPercent,
            reductionUnits = field("reductionUnits")?.double ?: fallback.reductionUnits,
            periodDays = field("periodDays")?.int ?: fallback.periodDays,
            start = start ?: fallback.start,
            targetWeekly = field("targetWeekly")?.double ?: fallback.targetWeekly,
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
