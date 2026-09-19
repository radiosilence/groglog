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
    /// When each drink-and-size was last poured (keyed by `Serve.key`), for putting your usuals first.
    let lastPoured: [String: Date]
    private let byDay: [Date: [Pour]]
    private let dry: Set<Date>

    init(pours: [Pour], dryDays: [AlcoholFreeDay], clock: DayClock) {
        self.clock = clock
        byDay = Dictionary(grouping: pours.sorted { $0.timestamp < $1.timestamp }) { clock.day(for: $0.timestamp) }
        dry = Set(dryDays.map(\.day))
        firstDay = (Array(byDay.keys) + Array(dry)).min()
        lastPoured = pours.reduce(into: [:]) { latest, pour in
            latest[pour.serveKey] = max(latest[pour.serveKey] ?? .distantPast, pour.timestamp)
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

    /// The unit budget for `day`: the taper, held at the target once it gets there.
    func dailyBudget(on day: Date, goal: Goal) -> Double? {
        taper(on: day, goal: goal).map { max($0.budget, min(goal.targetWeekly / 7, $0.reference)) }
    }

    /// When today's taper, carried on, reaches the target — and drops under a unit a day, the point where stopping is a small step.
    func projection(goal: Goal) -> (target: Date?, underOneUnit: Date?) {
        guard let today = taper(on: clock.today, goal: goal), goal.dailyCut > 0 else { return (nil, nil) }
        func date(reaching level: Double) -> Date? {
            guard level > 0 else { return nil }
            let days = today.budget <= level ? 0 : log(level / today.budget) / log(1 - goal.dailyCut)
            return clock.adding(Int(days.rounded(.up)), to: clock.today)
        }
        return (date(reaching: goal.targetWeekly / 7), date(reaching: 1))
    }

    /// The unfloored budget for `day` and the level it tapers from. Scheduled: from the baseline on the start date.
    /// Dynamic: the cut applied to your average over the previous period (dry days count as zero, unlogged days are
    /// left out), continuing the taper daily for future days. No history to go on means no budget.
    private func taper(on day: Date, goal: Goal) -> (budget: Double, reference: Double)? {
        guard goal.isEnabled else { return nil }
        let calendar = clock.calendar
        guard goal.isDynamic else {
            let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: goal.start), to: day).day ?? 0
            guard elapsed >= 0 else { return nil }
            let reference = goal.baselineWeekly / 7
            return (reference * pow(1 - goal.dailyCut, Double(elapsed)), reference)
        }
        // The period before the day — or, after a gap, the period ending at the last logged day within four weeks.
        let anchor = min(day, clock.today)
        let isLogged = { (day: Date) in [.drank, .alcoholFree].contains(self.status(on: day)) }
        guard let lastLogged = (1...28).map({ clock.adding(-$0, to: anchor) }).first(where: isLogged) else { return nil }
        let window = (0..<max(1, goal.periodDays)).map { clock.adding(-$0, to: lastLogged) }.filter(isLogged)
        let average = window.reduce(0) { $0 + totals(on: $1).units } / Double(window.count)
        let daysAhead = max(0, calendar.dateComponents([.day], from: anchor, to: day).day ?? 0)
        return (average * (1 - goal.reductionPercent / 100) * pow(1 - goal.dailyCut, Double(daysAhead)), average)
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
