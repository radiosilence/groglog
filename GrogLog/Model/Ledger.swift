import Foundation
import GrogLogCore

nonisolated enum DayStatus: Equatable {
    case drank, alcoholFree, today, unlogged, future, untracked
}

nonisolated struct DayTotals: Equatable {
    var units = 0.0
    var kcal = 0.0
    var cost = 0.0
    var count = 0

    init() {}

    init(_ totals: TotalsRow) {
        units = totals.units
        kcal = totals.kcal
        cost = totals.cost
        count = Int(totals.count)
    }

    static func + (lhs: DayTotals, rhs: DayTotals) -> DayTotals {
        var sum = lhs
        sum.units += rhs.units
        sum.kcal += rhs.kcal
        sum.cost += rhs.cost
        sum.count += rhs.count
        return sum
    }
}

/// A point on a running total: `x` is hours into a day, or days into a week or month.
nonisolated struct CurvePoint: Identifiable, Equatable {
    var x: Double
    var units: Double
    var id: Double { x }

    init(x: Double, units: Double) {
        self.x = x
        self.units = units
    }

    init(_ point: PointRow) {
        self.init(x: point.x, units: point.units)
    }
}

nonisolated struct WeekStat: Identifiable, Equatable {
    var start: DayKey
    var totals: DayTotals
    var dryDays: Int
    var unloggedDays: Int
    var budget: Double?
    var id: DayKey { start }
}

/// Read-only view over every drinking day, built from `Day` rows (a few hundred a year) so it is cheap to rebuild on
/// each change. The running-total curves need individual drinks and take them from the caller, fetched for only the
/// days on screen. The maths is the shared core's; this works out what needs the calendar (which day a moment is in,
/// how many hours into it) and hands over plain values.
nonisolated struct Ledger: Equatable {
    let clock: DayClock
    let today: DayKey
    let firstDay: DayKey?
    private let rows: [Day]
    private let core: CoreLedger

    init(days rows: [Day], clock: DayClock) {
        self.clock = clock
        today = clock.today
        self.rows = rows
        core = CoreLedger(days: rows.map(DayRow.init), today: Int64(today.number), firstWeekday: Int64(clock.calendar.firstWeekday))
        firstDay = core.firstDay().map { DayKey(number: Int($0)) }
    }

    static func == (lhs: Ledger, rhs: Ledger) -> Bool {
        lhs.clock == rhs.clock && lhs.today == rhs.today && lhs.rows == rhs.rows
    }

    func totals(on day: DayKey) -> DayTotals { DayTotals(core.totals(day: Int64(day.number))) }

    /// The manually set spend for a day, which replaces the drinks' prices while set.
    func spendOverride(on day: DayKey) -> Double? { core.spendOverride(day: Int64(day.number)) }

    /// The sum of the day's drink prices, ignoring any manual spend.
    func derivedSpend(on day: DayKey) -> Double { core.derivedSpend(day: Int64(day.number)) }

    func status(on day: DayKey) -> DayStatus { DayStatus(core.status(day: Int64(day.number))) }

    /// Has drinks or a dry mark. A day with only a manual spend is not logged.
    func isLogged(_ day: DayKey) -> Bool { core.isLogged(day: Int64(day.number)) }

    /// Consecutive alcohol-free days up to today. An empty today does not break the streak, since the day is not
    /// over.
    func dryStreak() -> Int { Int(core.dryStreak()) }

    func longestDryStreak(in range: ClosedRange<DayKey>) -> Int {
        Int(core.longestDryStreak(first: Int64(range.lowerBound.number), last: Int64(range.upperBound.number)))
    }

    /// The week before `day`, which a day is compared against.
    func weekBefore(_ day: DayKey) -> ClosedRange<DayKey> { (day - 7)...(day - 1) }

    /// Running units total across `days`, stepping at each drink. x is in days, so a heavy night shows as a steep
    /// climb rather than a single step.
    func runningTotal(_ entries: [Entry], over days: ClosedRange<DayKey>, through: DayKey? = nil) -> [CurvePoint] {
        core.runningTotal(
            entries: curveInputs(entries, over: days),
            first: Int64(days.lowerBound.number),
            last: Int64(days.upperBound.number),
            through: through.map { Int64($0.number) }
        ).map(CurvePoint.init)
    }

    /// The week's budget as a running total, for comparing with `runningTotal`.
    func weekBudgetCurve(of start: DayKey, goal: Goal) -> [CurvePoint] {
        core.weekBudgetCurve(start: Int64(start.number), goal: spec(goal)).map(CurvePoint.init)
    }

    func week(starting start: DayKey, goal: Goal) -> WeekStat {
        let week = core.week(start: Int64(start.number), goal: spec(goal))
        return WeekStat(
            start: start,
            totals: DayTotals(week.totals),
            dryDays: Int(week.dryDays),
            unloggedDays: Int(week.unloggedDays),
            budget: week.budget
        )
    }

    /// Units a week at the rate drunk on the logged days in `range`. Unlogged days are excluded rather than counted
    /// as dry, so missing nights do not make a week look light. Nil when nothing in the range was logged.
    func weeklyAverage(over range: ClosedRange<DayKey>) -> Double? {
        core.weeklyAverage(first: Int64(range.lowerBound.number), last: Int64(range.upperBound.number))
    }

    /// The same over the last `weeks` complete weeks, used as the default baseline for a reduction plan.
    func recentWeeklyAverage(weeks: Int = 4) -> Double? { core.recentWeeklyAverage(weeks: Int64(weeks)) }

    // MARK: Budget

    /// The unit budget for `day`: the taper, held at the target once it gets there.
    func dailyBudget(on day: DayKey, goal: Goal) -> Double? { core.dailyBudget(goal: spec(goal), day: Int64(day.number)) }

    /// How many days the budget takes to lose a tenth on `day`: the chosen period, or for a stepped taper the pace
    /// of the rung its budget has reached (the baseline's rung before it starts).
    func pace(on day: DayKey, goal: Goal) -> Int { Int(goalPaceOn(goal: spec(goal), day: Int64(day.number))) }

    /// When the taper, continued from today, reaches the target and the level at which drinking can stop
    /// (`Goal.stopFrom`).
    func projection(goal: Goal) -> (target: DayKey?, stoppable: DayKey?) {
        let projection = core.projection(goal: spec(goal))
        return (projection.target.map { DayKey(number: Int($0)) }, projection.stoppable.map { DayKey(number: Int($0)) })
    }

    // MARK: Curves

    /// Running total of units through a day, as a step series from `from` to `through` hours after the day starts.
    func cumulative(_ pours: [Entry], on day: DayKey, from: Double = 0, through: Double = 24) -> [CurvePoint] {
        let start = clock.start(of: day)
        let timed = pours.filter { $0.day == day.number }.map { TimedUnits(hours: $0.timestamp.timeIntervalSince(start) / 3600, units: $0.units) }
        return ledgerCumulative(pours: timed, from: from, through: through).map(CurvePoint.init)
    }

    /// Mean running total across the logged days in `range`, smoothed over about half an hour. Unlogged days are
    /// excluded rather than counted as zero. `smoothed: false` gives the unsmoothed mean, for reading off as a
    /// number.
    func averageCumulative(_ pours: [Entry], over range: ClosedRange<DayKey>, from: Double = 0, smoothed: Bool = true) -> [CurvePoint] {
        core.averageCumulative(
            entries: curveInputs(pours, over: range),
            first: Int64(range.lowerBound.number),
            last: Int64(range.upperBound.number),
            from: from,
            smoothed: smoothed
        ).map(CurvePoint.init)
    }

    private func spec(_ goal: Goal) -> GoalSpec { goal.spec(startDay: DayKey(goal.start, in: clock.calendar)) }

    /// The hours into its day are the calendar's to work out, and a day's start is cached across a screen's drinks.
    /// Only the drinks in `days` are worked out and passed across.
    private func curveInputs(_ entries: [Entry], over days: ClosedRange<DayKey>) -> [CurveInput] {
        var hours = HourCounter(clock)
        return entries.filter { days.contains($0.dayKey) }.map {
            CurveInput(day: Int64($0.day), hours: hours.hours($0.timestamp, into: $0.dayKey), units: $0.units, order: $0.timestamp.timeIntervalSince1970)
        }
    }
}

nonisolated extension DayStatus {
    init(_ kind: StatusKind) {
        self = switch kind {
        case .drank: .drank
        case .alcoholFree: .alcoholFree
        case .today: .today
        case .unlogged: .unlogged
        case .future: .future
        case .untracked: .untracked
        }
    }
}

nonisolated extension DayRow {
    init(_ row: Day) {
        self.init(
            number: Int64(row.number),
            isAlcoholFree: row.isAlcoholFree,
            units: row.units,
            kcal: row.kcal,
            cost: row.cost,
            count: Int64(row.count),
            costOverride: row.costOverride
        )
    }
}
