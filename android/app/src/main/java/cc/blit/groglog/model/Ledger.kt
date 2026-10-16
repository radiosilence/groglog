package cc.blit.groglog.model

import kotlin.math.ceil
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

enum class DayStatus { DRANK, ALCOHOL_FREE, TODAY, UNLOGGED, FUTURE, UNTRACKED }

data class DayTotals(val units: Double = 0.0, val kcal: Double = 0.0, val cost: Double = 0.0, val count: Int = 0) {
    operator fun plus(other: DayTotals) = DayTotals(units + other.units, kcal + other.kcal, cost + other.cost, count + other.count)

    companion object {
        fun of(row: Day) = DayTotals(row.units, row.kcal, row.spend, row.count)

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
 * screen.
 */
class Ledger(rows: List<Day>, val clock: DayClock) {
    val today: DayKey = clock.today
    private val days: Map<Int, Day> = buildMap { for (row in rows) putIfAbsent(row.number, row) }
    val firstDay: DayKey? = days.keys.minOrNull()?.let(::DayKey)

    override fun equals(other: Any?) =
        other is Ledger && other.clock == clock && other.today == today && other.days == days

    override fun hashCode() = days.hashCode() * 31 + today.hashCode()

    fun totals(day: DayKey): DayTotals = days[day.number]?.let(DayTotals::of) ?: DayTotals()

    /** The manually set spend for a day, which replaces the drinks' prices while set. */
    fun spendOverride(day: DayKey): Double? = days[day.number]?.costOverride

    /** The sum of the day's drink prices, ignoring any manual spend. */
    fun derivedSpend(day: DayKey): Double = days[day.number]?.cost ?: 0.0

    fun status(day: DayKey): DayStatus {
        days[day.number]?.let { row ->
            if (row.count > 0) return DayStatus.DRANK
            if (row.isAlcoholFree) return DayStatus.ALCOHOL_FREE
        }
        if (day > today) return DayStatus.FUTURE
        if (day == today) return DayStatus.TODAY
        val first = firstDay
        if (first == null || day < first) return DayStatus.UNTRACKED
        return DayStatus.UNLOGGED
    }

    /** Has drinks or a dry mark. A day with only a manual spend is not logged. */
    fun isLogged(day: DayKey): Boolean = days[day.number]?.let { it.count > 0 || it.isAlcoholFree } ?: false

    /** Consecutive alcohol-free days up to today. An empty today does not break the streak, since the day is not over. */
    fun dryStreak(): Int {
        var day = if (status(today) == DayStatus.TODAY) today - 1 else today
        var count = 0
        while (status(day) == DayStatus.ALCOHOL_FREE) {
            count += 1
            day -= 1
        }
        return count
    }

    fun longestDryStreak(range: DayRange): Int {
        var best = 0
        var run = 0
        for (day in range) {
            run = if (status(day) == DayStatus.ALCOHOL_FREE) run + 1 else 0
            best = max(best, run)
        }
        return best
    }

    /** The week before `day`, which a day is compared against. */
    fun weekBefore(day: DayKey): DayRange = (day - 7)..(day - 1)

    /**
     * Running units total across `days`, stepping at each drink. x is in days, so a heavy night shows as a steep climb
     * rather than a single step.
     */
    fun runningTotal(entries: List<Entry>, days: DayRange, through: DayKey? = null): List<CurvePoint> {
        val last = through ?: days.endInclusive
        var total = 0.0
        val hours = HourCounter(clock)
        val points = mutableListOf(CurvePoint(0.0, 0.0))
        for (entry in entries.filter { it.dayKey in days && it.dayKey <= last }.sortedBy { it.timestamp }) {
            total += entry.units
            val into = days.start.distanceTo(entry.dayKey) + min(1.0, max(0.0, hours.hours(entry.timestamp, entry.dayKey) / 24))
            points += CurvePoint(into, total)
        }
        return points
    }

    /** The week's budget as a running total, for comparing with `runningTotal`. */
    fun weekBudgetCurve(start: DayKey, goal: Goal): List<CurvePoint> {
        var total = 0.0
        val points = mutableListOf(CurvePoint(0.0, 0.0))
        for (index in 0 until 7) {
            val budget = dailyBudget(start + index, goal) ?: return if (points.size > 1) points else emptyList()
            total += budget
            points += CurvePoint((index + 1).toDouble(), total)
        }
        return points
    }

    fun week(start: DayKey, goal: Goal): WeekStat {
        val days = start..(start + 6)
        val budgets = days.map { dailyBudget(it, goal) }
        return WeekStat(
            start = start,
            totals = days.fold(DayTotals()) { sum, day -> sum + totals(day) },
            dryDays = days.count { status(it) == DayStatus.ALCOHOL_FREE },
            unloggedDays = days.count { status(it) == DayStatus.UNLOGGED },
            budget = if (budgets.contains(null)) null else budgets.filterNotNull().sum(),
        )
    }

    /**
     * Units a week at the rate drunk on the logged days in `range`. Unlogged days are excluded rather than counted as
     * dry, so missing nights do not make a week look light. Null when nothing in the range was logged.
     */
    fun weeklyAverage(range: DayRange): Double? {
        val logged = range.filter(::isLogged)
        if (logged.isEmpty()) return null
        return logged.sumOf { totals(it).units } / logged.size * 7
    }

    /** The same over the last `weeks` complete weeks, used as the default baseline for a reduction plan. */
    fun recentWeeklyAverage(weeks: Int = 4): Double? {
        val thisWeek = clock.weekStart(today)
        return weeklyAverage((thisWeek - 7 * weeks)..(thisWeek - 1))
    }

    // Budget

    /** The unit budget for `day`: the taper, held at the target once it gets there. */
    fun dailyBudget(day: DayKey, goal: Goal): Double? =
        taper(day, goal)?.let { (budget, reference) -> max(budget, min(goal.targetWeekly / 7, reference)) }

    /**
     * How many days the budget takes to lose a tenth on `day`: the chosen period, or for a stepped taper the pace of
     * the rung its budget has reached (the baseline's rung before it starts).
     */
    fun pace(day: DayKey, goal: Goal): Int {
        if (goal.taper != Taper.DYNAMIC) return goal.periodDays
        return Goal.pace((taper(day, goal)?.first ?: (goal.baselineWeekly / 7)) * 7)
    }

    /**
     * When the taper, continued from today, reaches the target and the level at which drinking can stop
     * (`Goal.STOP_FROM`).
     */
    fun projection(goal: Goal): Projection {
        val now = taper(today, goal)?.first ?: return Projection(null, null)
        val cutting = if (goal.taper == Taper.LINEAR) goal.dailyUnitCut > 0 else goal.dailyCut > 0
        if (!cutting) return Projection(null, null)
        fun day(level: Double): DayKey? {
            // A proportional taper crosses a level on a day given by a logarithm and never reaches zero. A linear taper
            // falls at a fixed rate and can reach zero, so only it answers for a level of zero.
            if (if (goal.taper == Taper.LINEAR) level < 0 else level <= 0) return null
            if (now <= level) return today
            val days = if (goal.taper == Taper.LINEAR) (now - level) / goal.dailyUnitCut else ln(level / now) / ln(1 - goal.dailyCut)
            return today + ceil(days).toInt()
        }
        return Projection(day(goal.targetWeekly / 7), day(Goal.STOP_FROM / 7))
    }

    /**
     * The unfloored budget for `day` and the level it tapers from. All tapers run from the baseline on the start date:
     * proportional takes a share off, linear a fixed number of units (so it can reach zero), and stepped takes the share
     * its ladder gives for the level the budget has reached.
     */
    private fun taper(day: DayKey, goal: Goal): Pair<Double, Double>? {
        if (!goal.isEnabled) return null
        val elapsed = DayKey.of(goal.start, clock.zone).distanceTo(day)
        if (elapsed < 0) return null
        val reference = goal.baselineWeekly / 7
        return when (goal.taper) {
            Taper.LINEAR -> max(0.0, reference - goal.dailyUnitCut * elapsed) to reference
            Taper.PROPORTIONAL -> reference * (1 - goal.dailyCut).pow(elapsed.toDouble()) to reference
            Taper.DYNAMIC -> {
                // Pace changes one rung at a time on the way down. Within a rung the decline is geometric, so the
                // crossing into the next rung is solved with a logarithm rather than by stepping day by day: this runs
                // for every calendar cell and chart point, and stepping a long-running goal would dominate those
                // screens.
                var budget = reference
                var days = elapsed
                for (rung in Goal.ladder) {
                    if (days <= 0 || budget * 7 <= rung.aboveWeekly) continue
                    val factor = 1 - Goal.rate(rung.pace)
                    var steps = days
                    if (rung.aboveWeekly > 0) {
                        // The first count of cuts that leaves it no longer above the rung, adjusted either way so a
                        // floating-point error in the logarithm cannot misplace the crossing by a day.
                        steps = max(0, ceil(ln(rung.aboveWeekly / (budget * 7)) / ln(factor)).toInt())
                        while (steps > 0 && budget * factor.pow(steps - 1) * 7 <= rung.aboveWeekly) steps -= 1
                        while (budget * factor.pow(steps) * 7 > rung.aboveWeekly) steps += 1
                        steps = min(steps, days)
                    }
                    budget *= factor.pow(steps)
                    days -= steps
                }
                budget to reference
            }
        }
    }

    // Curves

    /** Running total of units through a day, as a step series from `from` to `through` hours after the day starts. */
    fun cumulative(pours: List<Entry>, day: DayKey, from: Double = 0.0, through: Double = 24.0): List<CurvePoint> {
        val timed = pours.filter { it.day == day.number }.map { clock.hours(it.timestamp, day) to it.units }
        var total = timed.filter { it.first <= from }.sumOf { it.second }
        val points = mutableListOf(CurvePoint(from, total))
        for ((hour, units) in timed) {
            if (hour <= from || hour > through) continue
            total += units
            points += CurvePoint(hour, total)
        }
        points += CurvePoint(through, total)
        return points
    }

    /**
     * Mean running total across the logged days in `range`, smoothed over about three hours. Unlogged days are excluded
     * rather than counted as zero. The raw mean is a staircase of small steps; the line is meant to show where a typical
     * day stands by a given hour, so it is smoothed. `smoothed = false` gives the unsmoothed mean, for reading off as a
     * number.
     */
    fun averageCumulative(pours: List<Entry>, range: DayRange, from: Double = 0.0, smoothed: Boolean = true): List<CurvePoint> {
        val logged = range.filter(::isLogged)
        if (logged.isEmpty()) return emptyList()
        val hours = HourCounter(clock)
        val timed = pours
            .filter { it.dayKey in range }
            .map { hours.hours(it.timestamp, it.dayKey) to it.units }
            .sortedBy { it.first }
        var total = 0.0
        var index = 0
        val steps = ((24 - from) / 0.25).toInt()
        val raw = (0..steps).map { i ->
            val hour = from + i * 0.25
            while (index < timed.size && timed[index].first <= hour) {
                total += timed[index].second
                index += 1
            }
            CurvePoint(hour, total / logged.size)
        }
        if (!smoothed) return raw
        // The result must remain a running total: starting at zero, never falling, and ending on the mean. So the
        // drinks are spread over a few hours and re-accumulated, then scaled to preserve the total. Blurring the curve
        // itself would drag its ends inwards.
        var previous = 0.0
        val poured = raw.map { point -> (point.units - previous).also { previous = point.units } }
        val week = poured.sum()
        if (week <= 0) return raw
        // Twelve quarter-hours either side, applied twice, so the kernel tapers at the edges instead of cutting off as
        // a single box pass would.
        val span = 12
        val blur = { xs: List<Double> ->
            xs.indices.map { i -> (max(0, i - span)..min(xs.size - 1, i + span)).sumOf { xs[it] } / (2 * span + 1) }
        }
        val spread = blur(blur(poured))
        // The blur pushes a little past the end of the day, where it is lost; scaling restores it.
        val scale = week / spread.sum()
        var running = 0.0
        return raw.zip(spread) { point, amount ->
            running += amount * scale
            CurvePoint(point.x, running)
        }
    }
}
