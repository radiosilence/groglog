import Foundation

enum DayStatus {
    case drank, alcoholFree, today, unlogged, future, untracked
}

struct DayTotals {
    var units = 0.0
    var kcal = 0.0
    var cost = 0.0
    var count = 0

    init(_ pours: some Sequence<Pour> = []) {
        for pour in pours {
            units += pour.units
            kcal += pour.kcal
            cost += pour.price
            count += 1
        }
    }
}

struct CurvePoint: Identifiable {
    var hour: Double
    var units: Double
    var id: Double { hour }
}

struct WeekStat: Identifiable {
    var start: Date
    var totals: DayTotals
    var dryDays: Int
    var unloggedDays: Int
    var budget: Double?
    var id: Date { start }
}

/// Read-only view over everything logged, grouped into drinking days.
struct Ledger {
    let clock: DayClock
    let firstDay: Date?
    /// When each drink was last poured, for putting your usuals first.
    let lastPoured: [UUID: Date]
    private let byDay: [Date: [Pour]]
    private let dry: Set<Date>

    init(pours: [Pour], dryDays: [AlcoholFreeDay], clock: DayClock) {
        self.clock = clock
        byDay = Dictionary(grouping: pours.sorted { $0.timestamp < $1.timestamp }) { clock.day(for: $0.timestamp) }
        dry = Set(dryDays.map(\.day))
        firstDay = (Array(byDay.keys) + Array(dry)).min()
        lastPoured = pours.reduce(into: [:]) { latest, pour in
            guard let id = pour.drinkID else { return }
            latest[id] = max(latest[id] ?? .distantPast, pour.timestamp)
        }
    }

    func pours(on day: Date) -> [Pour] { byDay[day] ?? [] }
    func totals(on day: Date) -> DayTotals { DayTotals(pours(on: day)) }

    func status(on day: Date) -> DayStatus {
        if byDay[day] != nil { return .drank }
        if dry.contains(day) { return .alcoholFree }
        let today = clock.today
        if day > today { return .future }
        if day == today { return .today }
        guard let firstDay, day >= firstDay else { return .untracked }
        return .unlogged
    }

    func days(from start: Date, through end: Date) -> [Date] {
        var days: [Date] = []
        var day = start
        while day <= end {
            days.append(day)
            day = clock.adding(1, to: day)
        }
        return days
    }

    /// Consecutive alcohol-free days up to today. An empty today doesn't break the streak — the night is young.
    func dryStreak() -> Int {
        var day = clock.today
        if status(on: day) == .today { day = clock.adding(-1, to: day) }
        var count = 0
        while status(on: day) == .alcoholFree {
            count += 1
            day = clock.adding(-1, to: day)
        }
        return count
    }

    func longestDryStreak(in days: [Date]) -> Int {
        var best = 0
        var run = 0
        for day in days {
            run = status(on: day) == .alcoholFree ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// Running total of units through a day, as a step series from `from` to `through` hours after the day starts.
    func cumulative(on day: Date, from: Double = 0, through: Double = 24) -> [CurvePoint] {
        let timed = pours(on: day).map { (hour: clock.hours($0.timestamp, into: day), units: $0.units) }
        var total = timed.filter { $0.hour <= from }.reduce(0) { $0 + $1.units }
        var points = [CurvePoint(hour: from, units: total)]
        for pour in timed where pour.hour > from && pour.hour <= through {
            total += pour.units
            points.append(CurvePoint(hour: pour.hour, units: total))
        }
        points.append(CurvePoint(hour: through, units: total))
        return points
    }

    /// The days before `day` in its calendar month, falling back to the previous 30 days early in the month.
    func monthBefore(_ day: Date) -> [Date] {
        let monthStart = clock.calendar.dateInterval(of: .month, for: day)!.start
        let start = clock.calendar.dateComponents([.day], from: monthStart, to: day).day! >= 7 ? monthStart : clock.adding(-30, to: day)
        return days(from: start, through: clock.adding(-1, to: day))
    }

    /// Mean running total across the logged days among `days`. Unlogged days are left out rather than counted as zero.
    func averageCumulative(of days: [Date], from: Double = 0) -> [CurvePoint] {
        let prior = days.filter { [.drank, .alcoholFree].contains(status(on: $0)) }
        guard !prior.isEmpty else { return [] }
        let timed = prior.flatMap { d in pours(on: d).map { (hour: clock.hours($0.timestamp, into: d), units: $0.units) } }
        return stride(from: from, through: 24, by: 0.25).map { hour in
            let total = timed.filter { $0.hour <= hour }.reduce(0) { $0 + $1.units }
            return CurvePoint(hour: hour, units: total / Double(prior.count))
        }
    }

    /// Running units total by day-of-month, through `through` (or the month's end).
    func monthCumulative(_ month: Date, through: Date? = nil) -> [CurvePoint] {
        let calendar = clock.calendar
        let days = calendar.range(of: .day, in: .month, for: month)!.map { calendar.date(byAdding: .day, value: $0 - 1, to: month)! }
        var total = 0.0
        var points = [CurvePoint(hour: 0, units: 0)]
        for (index, day) in days.enumerated() where through.map({ day <= $0 }) ?? true {
            total += totals(on: day).units
            points.append(CurvePoint(hour: Double(index + 1), units: total))
        }
        return points
    }

    /// The unit budget for `day`. On a fixed schedule it's the goal's own; "from today", it's the average of the last
    /// few drinking days before `day` (or before today, projecting forward) cut by the goal's daily rate.
    func dailyBudget(on day: Date, goal: Goal) -> Double? {
        guard goal.isEnabled else { return nil }
        guard goal.fromToday else { return goal.scheduledBudget(on: day, calendar: clock.calendar) }
        let today = clock.today
        let anchor = min(day, today)
        let recent = (1...14)
            .map { clock.adding(-$0, to: anchor) }
            .filter { status(on: $0) == .drank }
            .prefix(3)
        let level = recent.isEmpty ? goal.baselineWeekly / 7 : recent.reduce(0) { $0 + totals(on: $1).units } / Double(recent.count)
        let daysAhead = max(0, clock.calendar.dateComponents([.day], from: today, to: day).day ?? 0)
        let budget = level * pow(1 - goal.dailyCut, Double(1 + daysAhead))
        return max(min(goal.targetWeekly / 7, level), budget)
    }

    func week(starting start: Date, goal: Goal) -> WeekStat {
        let days = (0..<7).map { clock.adding($0, to: start) }
        let budgets = days.map { dailyBudget(on: $0, goal: goal) }
        return WeekStat(
            start: start,
            totals: DayTotals(days.flatMap(pours(on:))),
            dryDays: days.filter { status(on: $0) == .alcoholFree }.count,
            unloggedDays: days.filter { status(on: $0) == .unlogged }.count,
            budget: budgets.contains(nil) ? nil : budgets.compactMap(\.self).reduce(0, +)
        )
    }

    /// Mean weekly units over the last `weeks` complete weeks — the natural starting point for a reduction plan.
    func recentWeeklyAverage(weeks: Int = 4) -> Double? {
        let thisWeek = clock.weekStart(of: clock.today)
        let starts = (1...weeks).map { clock.adding(-7 * $0, to: thisWeek) }.filter { start in
            firstDay.map { clock.adding(7, to: start) > $0 } ?? false
        }
        guard !starts.isEmpty else { return nil }
        return starts.map { week(starting: $0, goal: Goal()).totals.units }.reduce(0, +) / Double(starts.count)
    }
}
