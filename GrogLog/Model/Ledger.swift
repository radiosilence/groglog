import Foundation

nonisolated enum DayStatus {
    case drank, alcoholFree, today, unlogged, future, untracked
}

nonisolated struct DayTotals {
    var units = 0.0
    var kcal = 0.0
    var cost = 0.0
    var count = 0

    init() {}

    init(_ entries: some Sequence<Entry>) {
        for entry in entries {
            units += entry.units
            kcal += entry.kcal
            cost += entry.price
            count += 1
        }
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

nonisolated struct CurvePoint: Identifiable {
    var hour: Double
    var units: Double
    var id: Double { hour }
}

nonisolated struct WeekStat: Identifiable {
    var start: DayKey
    var totals: DayTotals
    var dryDays: Int
    var unloggedDays: Int
    var budget: Double?
    var id: DayKey { start }
}

/// Read-only view over every drinking day, built from `Day` rows (a few hundred a year) so it's cheap to rebuild on
/// each change. Anything needing individual drinks — the running-total curves — takes them from the caller, fetched
/// for just the days on screen.
nonisolated struct Ledger {
    let clock: DayClock
    let today: DayKey
    let firstDay: DayKey?
    private let days: [Int: (totals: DayTotals, isAlcoholFree: Bool)]

    init(days rows: [Day], clock: DayClock) {
        self.clock = clock
        today = clock.today
        var days: [Int: (totals: DayTotals, isAlcoholFree: Bool)] = [:]
        days.reserveCapacity(rows.count)
        for row in rows {
            var totals = DayTotals()
            totals.units = row.units
            totals.kcal = row.kcal
            totals.cost = row.cost
            totals.count = row.count
            days[row.number] = (totals, row.isAlcoholFree)
        }
        self.days = days
        firstDay = days.keys.min().map(DayKey.init(number:))
    }

    func totals(on day: DayKey) -> DayTotals { days[day.number]?.totals ?? DayTotals() }

    func status(on day: DayKey) -> DayStatus {
        if let entry = days[day.number] {
            if entry.totals.count > 0 { return .drank }
            if entry.isAlcoholFree { return .alcoholFree }
        }
        if day > today { return .future }
        if day == today { return .today }
        guard let firstDay, day >= firstDay else { return .untracked }
        return .unlogged
    }

    /// Drank or marked dry — anything but a gap.
    func isLogged(_ day: DayKey) -> Bool { days[day.number] != nil }

    /// Consecutive alcohol-free days up to today. An empty today doesn't break the streak — the night is young.
    func dryStreak() -> Int {
        var day = status(on: today) == .today ? today - 1 : today
        var count = 0
        while status(on: day) == .alcoholFree {
            count += 1
            day = day - 1
        }
        return count
    }

    func longestDryStreak(in range: ClosedRange<DayKey>) -> Int {
        var best = 0
        var run = 0
        for day in range {
            run = status(on: day) == .alcoholFree ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// The days before `day` in its month, falling back to the previous 30 days early in the month.
    func monthBefore(_ day: DayKey) -> ClosedRange<DayKey> {
        let start = day.monthStart.distance(to: day) >= 7 ? day.monthStart : day - 30
        return start...(day - 1)
    }

    /// Running units total through a week, stepping at each drink — x is days into the week.
    func weekCurve(_ entries: [Entry], of start: DayKey, through: DayKey? = nil) -> [CurvePoint] {
        let days = start...(start + 6)
        let last = through ?? days.upperBound
        var total = 0.0
        var points = [CurvePoint(hour: 0, units: 0)]
        for entry in entries.filter({ days.contains($0.dayKey) && $0.dayKey <= last }).sorted(by: { $0.timestamp < $1.timestamp }) {
            total += entry.units
            let into = Double(start.distance(to: entry.dayKey)) + min(1, max(0, clock.hours(entry.timestamp, into: entry.dayKey) / 24))
            points.append(CurvePoint(hour: into, units: total))
        }
        return points
    }

    /// The week's budget as a running total, for comparing with `weekCurve`.
    func weekBudgetCurve(of start: DayKey, goal: Goal) -> [CurvePoint] {
        var total = 0.0
        var points = [CurvePoint(hour: 0, units: 0)]
        for index in 0..<7 {
            guard let budget = dailyBudget(on: start + index, goal: goal) else { return points.count > 1 ? points : [] }
            total += budget
            points.append(CurvePoint(hour: Double(index + 1), units: total))
        }
        return points
    }

    /// Running units total through a month, stepping at each drink — x is days into the month, so a heavy night
    /// shows as a steep climb rather than a single step.
    func monthCurve(_ entries: [Entry], of month: DayKey, through: DayKey? = nil) -> [CurvePoint] {
        let days = month...(month + month.daysInMonth - 1)
        var total = 0.0
        var points = [CurvePoint(hour: 0, units: 0)]
        let last = through ?? days.upperBound
        for entry in entries.filter({ days.contains($0.dayKey) && $0.dayKey <= last }).sorted(by: { $0.timestamp < $1.timestamp }) {
            total += entry.units
            let into = Double(month.distance(to: entry.dayKey)) + min(1, max(0, clock.hours(entry.timestamp, into: entry.dayKey) / 24))
            points.append(CurvePoint(hour: into, units: total))
        }
        return points
    }

    func week(starting start: DayKey, goal: Goal) -> WeekStat {
        let days = start...(start + 6)
        let budgets = days.map { dailyBudget(on: $0, goal: goal) }
        return WeekStat(
            start: start,
            totals: days.reduce(DayTotals()) { $0 + totals(on: $1) },
            dryDays: days.filter { status(on: $0) == .alcoholFree }.count,
            unloggedDays: days.filter { status(on: $0) == .unlogged }.count,
            budget: budgets.contains(nil) ? nil : budgets.compactMap(\.self).reduce(0, +)
        )
    }

    /// Mean weekly units over the last `weeks` complete weeks — the natural starting point for a reduction plan.
    func recentWeeklyAverage(weeks: Int = 4) -> Double? {
        let thisWeek = clock.weekStart(of: today)
        let starts = (1...weeks).map { thisWeek - 7 * $0 }.filter { start in firstDay.map { start + 7 > $0 } ?? false }
        guard !starts.isEmpty else { return nil }
        return starts.map { week(starting: $0, goal: Goal()).totals.units }.reduce(0, +) / Double(starts.count)
    }

    // MARK: Budget

    /// The unit budget for `day`: the taper, held at the target once it gets there.
    func dailyBudget(on day: DayKey, goal: Goal) -> Double? {
        taper(on: day, goal: goal).map { max($0.budget, min(goal.targetWeekly / 7, $0.reference)) }
    }

    /// When today's taper, carried on, reaches the target — and drops under a unit a day, the point where stopping is a small step.
    func projection(goal: Goal) -> (target: DayKey?, underOneUnit: DayKey?) {
        guard let now = taper(on: today, goal: goal), goal.dailyCut > 0 else { return (nil, nil) }
        func day(reaching level: Double) -> DayKey? {
            guard level > 0 else { return nil }
            let days = now.budget <= level ? 0 : log(level / now.budget) / log(1 - goal.dailyCut)
            return today + Int(days.rounded(.up))
        }
        return (day(reaching: goal.targetWeekly / 7), day(reaching: 1))
    }

    /// The unfloored budget for `day` and the level it tapers from. Scheduled: from the baseline on the start date.
    /// Dynamic: the cut applied to your average over the previous period (dry days count as zero, unlogged days are
    /// left out) — after a gap, the period ending at the last logged day within four weeks — continuing the taper
    /// daily for future days. No history to go on means no budget.
    private func taper(on day: DayKey, goal: Goal) -> (budget: Double, reference: Double)? {
        guard goal.isEnabled else { return nil }
        guard goal.isDynamic else {
            let start = clock.calendar.dateComponents([.year, .month, .day], from: goal.start)
            let elapsed = DayKey(year: start.year!, month: start.month!, day: start.day!).distance(to: day)
            guard elapsed >= 0 else { return nil }
            let reference = goal.baselineWeekly / 7
            return (reference * pow(1 - goal.dailyCut, Double(elapsed)), reference)
        }
        let anchor = min(day, today)
        guard let lastLogged = (1...28).lazy.map({ anchor - $0 }).first(where: isLogged) else { return nil }
        let window = (0..<max(1, goal.periodDays)).map { lastLogged - $0 }.filter(isLogged)
        let average = window.reduce(0) { $0 + totals(on: $1).units } / Double(window.count)
        let daysAhead = max(0, anchor.distance(to: day))
        return (average * (1 - goal.reductionPercent / 100) * pow(1 - goal.dailyCut, Double(daysAhead)), average)
    }

    // MARK: Curves

    /// Units drunk in the 24 hours up to each hour across `range` — the shape of the drinking itself, comparable with
    /// a daily budget. Entries must cover the range (plus the day before it).
    func rollingDay(_ entries: [Entry], over range: ClosedRange<DayKey>) -> [(date: Date, units: Double)] {
        let times = entries.map { (at: $0.timestamp, units: $0.units) }.sorted { $0.at < $1.at }
        guard !times.isEmpty else { return [] }
        let start = clock.start(of: range.lowerBound)
        let end = min(clock.end(of: range.upperBound), .now)
        guard start < end else { return [] }
        var points: [(Date, Double)] = []
        var total = 0.0
        var entering = 0
        var leaving = 0
        for step in stride(from: start.timeIntervalSinceReferenceDate, through: end.timeIntervalSinceReferenceDate, by: 3600) {
            let at = Date(timeIntervalSinceReferenceDate: step)
            while entering < times.count, times[entering].at <= at {
                total += times[entering].units
                entering += 1
            }
            while leaving < entering, times[leaving].at <= at.addingTimeInterval(-24 * 3600) {
                total -= times[leaving].units
                leaving += 1
            }
            points.append((at, max(0, total)))
        }
        return points
    }

    /// Running total of units through a day, as a step series from `from` to `through` hours after the day starts.
    func cumulative(_ pours: [Entry], on day: DayKey, from: Double = 0, through: Double = 24) -> [CurvePoint] {
        let timed = pours.filter { $0.day == day.number }.map { (hour: clock.hours($0.timestamp, into: day), units: $0.units) }
        var total = timed.filter { $0.hour <= from }.reduce(0) { $0 + $1.units }
        var points = [CurvePoint(hour: from, units: total)]
        for pour in timed where pour.hour > from && pour.hour <= through {
            total += pour.units
            points.append(CurvePoint(hour: pour.hour, units: total))
        }
        points.append(CurvePoint(hour: through, units: total))
        return points
    }

    /// Mean running total across the logged days in `range`. Unlogged days are left out rather than counted as zero.
    func averageCumulative(_ pours: [Entry], over range: ClosedRange<DayKey>, from: Double = 0) -> [CurvePoint] {
        let logged = range.filter(isLogged)
        guard !logged.isEmpty else { return [] }
        let timed = pours
            .filter { range.contains($0.dayKey) }
            .map { (hour: clock.hours($0.timestamp, into: $0.dayKey), units: $0.units) }
            .sorted { $0.hour < $1.hour }
        var total = 0.0
        var index = 0
        return stride(from: from, through: 24, by: 0.25).map { hour in
            while index < timed.count, timed[index].hour <= hour {
                total += timed[index].units
                index += 1
            }
            return CurvePoint(hour: hour, units: total / Double(logged.count))
        }
    }
}
