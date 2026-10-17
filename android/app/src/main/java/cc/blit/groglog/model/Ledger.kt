package cc.blit.groglog.model

import cc.blit.groglog.core.CoreLedger
import cc.blit.groglog.core.CurveInput
import cc.blit.groglog.core.DayRow
import cc.blit.groglog.core.PointRow
import cc.blit.groglog.core.StatusKind
import cc.blit.groglog.core.TimedUnits
import cc.blit.groglog.core.TotalsRow
import cc.blit.groglog.core.goalPaceOn
import cc.blit.groglog.core.ledgerCumulative

enum class DayStatus { DRANK, ALCOHOL_FREE, TODAY, UNLOGGED, FUTURE, UNTRACKED }

data class DayTotals(val units: Double = 0.0, val kcal: Double = 0.0, val cost: Double = 0.0, val count: Int = 0) {
    operator fun plus(other: DayTotals) = DayTotals(units + other.units, kcal + other.kcal, cost + other.cost, count + other.count)

    companion object {
        fun of(row: Day) = DayTotals(row.units, row.kcal, row.spend, row.count)

        fun of(totals: TotalsRow) = DayTotals(totals.units, totals.kcal, totals.cost, totals.count.toInt())

        fun of(entries: Iterable<Entry>): DayTotals {
            var units = 0.0
            var kcal = 0.0
            var cost = 0.0
            var count = 0
            for (entry in entries) {
                units += entry.units
                kcal += entry.kcal
                cost += entry.price
                count += 1
            }
            return DayTotals(units, kcal, cost, count)
        }
    }
}

/** A point on a running total: `x` is hours into a day, or days into a week or month. */
data class CurvePoint(val x: Double, val units: Double) {
    val id: Double get() = x

    constructor(point: PointRow) : this(point.x, point.units)
}

data class WeekStat(
    val start: DayKey,
    val totals: DayTotals,
    val dryDays: Int,
    val unloggedDays: Int,
    val budget: Double?,
) {
    val id: DayKey get() = start
}

/** When a taper, continued from today, reaches its target and the level at which drinking can stop. */
data class Projection(val target: DayKey?, val stoppable: DayKey?)

/**
 * Read-only view over every drinking day, built from `Day` rows (a few hundred a year) so it is cheap to rebuild on each
 * change. The running-total curves need individual drinks and take them from the caller, fetched for only the days on
 * screen. The maths is the shared core's; this works out what needs the calendar (which day a moment is in, how many
 * hours into it) and hands over plain values.
 */
class Ledger(rows: List<Day>, val clock: DayClock) {
    val today: DayKey = clock.today
    private val days: Map<Int, Day> = buildMap { for (row in rows) putIfAbsent(row.number, row) }
    private val core = CoreLedger(
        rows.map { DayRow(it.number.toLong(), it.isAlcoholFree, it.units, it.kcal, it.cost, it.count.toLong(), it.costOverride) },
        today.number.toLong(),
        clock.firstWeekday.toLong(),
    )
    val firstDay: DayKey? = core.firstDay()?.let { DayKey(it.toInt()) }

    override fun equals(other: Any?) =
        other is Ledger && other.clock == clock && other.today == today && other.days == days

    override fun hashCode() = days.hashCode() * 31 + today.hashCode()

    fun totals(day: DayKey): DayTotals = DayTotals.of(core.totals(day.number.toLong()))

    /** The manually set spend for a day, which replaces the drinks' prices while set. */
    fun spendOverride(day: DayKey): Double? = core.spendOverride(day.number.toLong())

    /** The sum of the day's drink prices, ignoring any manual spend. */
    fun derivedSpend(day: DayKey): Double = core.derivedSpend(day.number.toLong())

    fun status(day: DayKey): DayStatus = when (core.status(day.number.toLong())) {
        StatusKind.DRANK -> DayStatus.DRANK
        StatusKind.ALCOHOL_FREE -> DayStatus.ALCOHOL_FREE
        StatusKind.TODAY -> DayStatus.TODAY
        StatusKind.UNLOGGED -> DayStatus.UNLOGGED
        StatusKind.FUTURE -> DayStatus.FUTURE
        StatusKind.UNTRACKED -> DayStatus.UNTRACKED
    }

    /** Has drinks or a dry mark. A day with only a manual spend is not logged. */
    fun isLogged(day: DayKey): Boolean = core.isLogged(day.number.toLong())

    /** Consecutive alcohol-free days up to today. An empty today does not break the streak, since the day is not over. */
    fun dryStreak(): Int = core.dryStreak().toInt()

    fun longestDryStreak(range: DayRange): Int =
        core.longestDryStreak(range.start.number.toLong(), range.endInclusive.number.toLong()).toInt()

    /** The week before `day`, which a day is compared against. */
    fun weekBefore(day: DayKey): DayRange = (day - 7)..(day - 1)

    /**
     * Running units total across `days`, stepping at each drink. x is in days, so a heavy night shows as a steep climb
     * rather than a single step.
     */
    fun runningTotal(entries: List<Entry>, days: DayRange, through: DayKey? = null): List<CurvePoint> =
        core.runningTotal(curveInputs(entries), days.start.number.toLong(), days.endInclusive.number.toLong(), through?.number?.toLong())
            .map(::CurvePoint)

    /** The week's budget as a running total, for comparing with `runningTotal`. */
    fun weekBudgetCurve(start: DayKey, goal: Goal): List<CurvePoint> =
        core.weekBudgetCurve(start.number.toLong(), spec(goal)).map(::CurvePoint)

    fun week(start: DayKey, goal: Goal): WeekStat {
        val week = core.week(start.number.toLong(), spec(goal))
        return WeekStat(start, DayTotals.of(week.totals), week.dryDays.toInt(), week.unloggedDays.toInt(), week.budget)
    }

    /**
     * Units a week at the rate drunk on the logged days in `range`. Unlogged days are excluded rather than counted as
     * dry, so missing nights do not make a week look light. Null when nothing in the range was logged.
     */
    fun weeklyAverage(range: DayRange): Double? = core.weeklyAverage(range.start.number.toLong(), range.endInclusive.number.toLong())

    /** The same over the last `weeks` complete weeks, used as the default baseline for a reduction plan. */
    fun recentWeeklyAverage(weeks: Int = 4): Double? = core.recentWeeklyAverage(weeks.toLong())

    // Budget

    /** The unit budget for `day`: the taper, held at the target once it gets there. */
    fun dailyBudget(day: DayKey, goal: Goal): Double? = core.dailyBudget(spec(goal), day.number.toLong())

    /**
     * How many days the budget takes to lose a tenth on `day`: the chosen period, or for a stepped taper the pace of the
     * rung its budget has reached (the baseline's rung before it starts).
     */
    fun pace(day: DayKey, goal: Goal): Int = goalPaceOn(spec(goal), day.number.toLong()).toInt()

    /** When the taper, continued from today, reaches the target and the level at which drinking can stop (`Goal.STOP_FROM`). */
    fun projection(goal: Goal): Projection {
        val projection = core.projection(spec(goal))
        return Projection(projection.target?.let { DayKey(it.toInt()) }, projection.stoppable?.let { DayKey(it.toInt()) })
    }

    // Curves

    /** Running total of units through a day, as a step series from `from` to `through` hours after the day starts. */
    fun cumulative(pours: List<Entry>, day: DayKey, from: Double = 0.0, through: Double = 24.0): List<CurvePoint> {
        val timed = pours.filter { it.day == day.number }.map { TimedUnits(clock.hours(it.timestamp, day), it.units) }
        return ledgerCumulative(timed, from, through).map(::CurvePoint)
    }

    /**
     * Mean running total across the logged days in `range`, smoothed over about half an hour. Unlogged days are excluded
     * rather than counted as zero. `smoothed = false` gives the unsmoothed mean, for reading off as a number.
     */
    fun averageCumulative(pours: List<Entry>, range: DayRange, from: Double = 0.0, smoothed: Boolean = true): List<CurvePoint> =
        core.averageCumulative(curveInputs(pours), range.start.number.toLong(), range.endInclusive.number.toLong(), from, smoothed)
            .map(::CurvePoint)

    private fun spec(goal: Goal) = goal.spec(DayKey.of(goal.start, clock.zone))

    /** The hours into a drink's day are the calendar's to work out, and a day's start is cached across a screen's drinks. */
    private fun curveInputs(entries: List<Entry>): List<CurveInput> {
        val hours = HourCounter(clock)
        return entries.map {
            CurveInput(it.day.toLong(), hours.hours(it.timestamp, it.dayKey), it.units, it.timestamp.toEpochMilli() / 1000.0)
        }
    }
}
