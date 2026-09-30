import Foundation

nonisolated enum DayStatus: Equatable {
    case drank, alcoholFree, today, unlogged, future, untracked
}

nonisolated struct DayTotals: Equatable {
    var units = 0.0
    var kcal = 0.0
    var cost = 0.0
    var count = 0

    init() {}

    init(_ row: Day) {
        units = row.units
        kcal = row.kcal
        cost = row.spend
        count = row.count
    }

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

/// A point on a running total: `x` is hours into a day, or days into a week or month.
nonisolated struct CurvePoint: Identifiable, Equatable {
    var x: Double
    var units: Double
    var id: Double { x }
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
/// days on screen.
nonisolated struct Ledger: Equatable {
    let clock: DayClock
    let today: DayKey
    let firstDay: DayKey?
    private let days: [Int: Day]

    init(days rows: [Day], clock: DayClock) {
        self.clock = clock
        today = clock.today
        days = Dictionary(rows.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        firstDay = days.keys.min().map(DayKey.init(number:))
    }

    func totals(on day: DayKey) -> DayTotals { days[day.number].map(DayTotals.init) ?? DayTotals() }

    /// The manually set spend for a day, which replaces the drinks' prices while set.
    func spendOverride(on day: DayKey) -> Double? { days[day.number]?.costOverride }

    /// The sum of the day's drink prices, ignoring any manual spend.
    func derivedSpend(on day: DayKey) -> Double { days[day.number]?.cost ?? 0 }

    func status(on day: DayKey) -> DayStatus {
        if let row = days[day.number] {
            if row.count > 0 { return .drank }
            if row.isAlcoholFree { return .alcoholFree }
        }
        if day > today { return .future }
        if day == today { return .today }
        guard let firstDay, day >= firstDay else { return .untracked }
        return .unlogged
    }

    /// Has drinks or a dry mark. A day with only a manual spend is not logged.
    func isLogged(_ day: DayKey) -> Bool { days[day.number].map { $0.count > 0 || $0.isAlcoholFree } ?? false }

    /// Consecutive alcohol-free days up to today. An empty today does not break the streak, since the day is not
    /// over.
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

    /// The week before `day`, which a day is compared against.
    func weekBefore(_ day: DayKey) -> ClosedRange<DayKey> { (day - 7)...(day - 1) }

    /// Running units total across `days`, stepping at each drink. x is in days, so a heavy night shows as a steep
    /// climb rather than a single step.
    func runningTotal(_ entries: [Entry], over days: ClosedRange<DayKey>, through: DayKey? = nil) -> [CurvePoint] {
        let last = through ?? days.upperBound
        var total = 0.0
        var hours = HourCounter(clock)
        var points = [CurvePoint(x: 0, units: 0)]
        for entry in entries.filter({ days.contains($0.dayKey) && $0.dayKey <= last }).sorted(by: { $0.timestamp < $1.timestamp }) {
            total += entry.units
            let into = Double(days.lowerBound.distance(to: entry.dayKey)) + min(1, max(0, hours.hours(entry.timestamp, into: entry.dayKey) / 24))
            points.append(CurvePoint(x: into, units: total))
        }
        return points
    }

    /// The week's budget as a running total, for comparing with `runningTotal`.
    func weekBudgetCurve(of start: DayKey, goal: Goal) -> [CurvePoint] {
        var total = 0.0
        var points = [CurvePoint(x: 0, units: 0)]
        for index in 0..<7 {
            guard let budget = dailyBudget(on: start + index, goal: goal) else { return points.count > 1 ? points : [] }
            total += budget
            points.append(CurvePoint(x: Double(index + 1), units: total))
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

    /// Units a week at the rate drunk on the logged days in `range`. Unlogged days are excluded rather than counted
    /// as dry, so missing nights do not make a week look light. Nil when nothing in the range was logged.
    func weeklyAverage(over range: ClosedRange<DayKey>) -> Double? {
        let logged = range.filter(isLogged)
        guard !logged.isEmpty else { return nil }
        return logged.reduce(0) { $0 + totals(on: $1).units } / Double(logged.count) * 7
    }

    /// The same over the last `weeks` complete weeks, used as the default baseline for a reduction plan.
    func recentWeeklyAverage(weeks: Int = 4) -> Double? {
        let thisWeek = clock.weekStart(of: today)
        return weeklyAverage(over: (thisWeek - 7 * weeks)...(thisWeek - 1))
    }

    // MARK: Budget

    /// The unit budget for `day`: the taper, held at the target once it gets there.
    func dailyBudget(on day: DayKey, goal: Goal) -> Double? {
        taper(on: day, goal: goal).map { max($0.budget, min(goal.targetWeekly / 7, $0.reference)) }
    }

    /// How many days the budget takes to lose a tenth on `day`: the chosen period, or for a stepped taper the pace
    /// of the rung its budget has reached (the baseline's rung before it starts).
    func pace(on day: DayKey, goal: Goal) -> Int {
        guard goal.taper == .dynamic else { return goal.periodDays }
        return Goal.pace(drinking: (taper(on: day, goal: goal)?.budget ?? goal.baselineWeekly / 7) * 7)
    }

    /// When the taper, continued from today, reaches the target and the level at which drinking can stop
    /// (`Goal.stopFrom`).
    func projection(goal: Goal) -> (target: DayKey?, stoppable: DayKey?) {
        guard let now = taper(on: today, goal: goal) else { return (nil, nil) }
        guard goal.taper == .linear ? goal.dailyUnitCut > 0 : goal.dailyCut > 0 else { return (nil, nil) }
        func day(reaching level: Double) -> DayKey? {
            // A proportional taper crosses a level on a day given by a logarithm and never reaches zero. A linear
            // taper falls at a fixed rate and can reach zero, so only it answers for a level of zero.
            guard goal.taper == .linear ? level >= 0 : level > 0 else { return nil }
            if now.budget <= level { return today }
            let days = goal.taper == .linear
                ? (now.budget - level) / goal.dailyUnitCut
                : log(level / now.budget) / log(1 - goal.dailyCut)
            return today + Int(days.rounded(.up))
        }
        return (day(reaching: goal.targetWeekly / 7), day(reaching: Goal.stopFrom / 7))
    }

    /// The unfloored budget for `day` and the level it tapers from. All tapers run from the baseline on the start
    /// date: proportional takes a share off, linear a fixed number of units (so it can reach zero), and stepped
    /// takes the share its ladder gives for the level the budget has reached.
    private func taper(on day: DayKey, goal: Goal) -> (budget: Double, reference: Double)? {
        guard goal.isEnabled else { return nil }
        let elapsed = DayKey(goal.start, in: clock.calendar).distance(to: day)
        guard elapsed >= 0 else { return nil }
        let reference = goal.baselineWeekly / 7
        switch goal.taper {
        case .linear:
            return (max(0, reference - goal.dailyUnitCut * Double(elapsed)), reference)
        case .proportional:
            return (reference * pow(1 - goal.dailyCut, Double(elapsed)), reference)
        case .dynamic:
            // Pace changes one rung at a time on the way down. Within a rung the decline is geometric, so the
            // crossing into the next rung is solved with a logarithm rather than by stepping day by day: this runs
            // for every calendar cell and chart point, and stepping a long-running goal would dominate those
            // screens.
            var budget = reference
            var days = elapsed
            for rung in Goal.ladder where days > 0 && budget * 7 > rung.aboveWeekly {
                let factor = 1 - Goal.rate(forPace: rung.pace)
                var steps = days
                if rung.aboveWeekly > 0 {
                    // The first count of cuts that leaves it no longer above the rung, adjusted either way so a
                    // floating-point error in the logarithm cannot misplace the crossing by a day.
                    steps = max(0, Int((log(rung.aboveWeekly / (budget * 7)) / log(factor)).rounded(.up)))
                    while steps > 0, budget * pow(factor, Double(steps - 1)) * 7 <= rung.aboveWeekly { steps -= 1 }
                    while budget * pow(factor, Double(steps)) * 7 > rung.aboveWeekly { steps += 1 }
                    steps = min(steps, days)
                }
                budget *= pow(factor, Double(steps))
                days -= steps
            }
            return (budget, reference)
        }
    }


    // MARK: Curves

    /// Running total of units through a day, as a step series from `from` to `through` hours after the day starts.
    func cumulative(_ pours: [Entry], on day: DayKey, from: Double = 0, through: Double = 24) -> [CurvePoint] {
        let start = clock.start(of: day)
        let timed = pours.filter { $0.day == day.number }.map { (hour: $0.timestamp.timeIntervalSince(start) / 3600, units: $0.units) }
        var total = timed.filter { $0.hour <= from }.reduce(0) { $0 + $1.units }
        var points = [CurvePoint(x: from, units: total)]
        for pour in timed where pour.hour > from && pour.hour <= through {
            total += pour.units
            points.append(CurvePoint(x: pour.hour, units: total))
        }
        points.append(CurvePoint(x: through, units: total))
        return points
    }

    /// Mean running total across the logged days in `range`, smoothed over about three hours. Unlogged days are
    /// excluded rather than counted as zero. The raw mean is a staircase of small steps; the line is meant to show
    /// where a typical day stands by a given hour, so it is smoothed. `smoothed: false` gives the unsmoothed mean,
    /// for reading off as a number.
    func averageCumulative(_ pours: [Entry], over range: ClosedRange<DayKey>, from: Double = 0, smoothed: Bool = true) -> [CurvePoint] {
        let logged = range.filter(isLogged)
        guard !logged.isEmpty else { return [] }
        var hours = HourCounter(clock)
        let timed = pours
            .filter { range.contains($0.dayKey) }
            .map { (hour: hours.hours($0.timestamp, into: $0.dayKey), units: $0.units) }
            .sorted { $0.hour < $1.hour }
        var total = 0.0
        var index = 0
        let raw = stride(from: from, through: 24, by: 0.25).map { hour -> CurvePoint in
            while index < timed.count, timed[index].hour <= hour {
                total += timed[index].units
                index += 1
            }
            return CurvePoint(x: hour, units: total / Double(logged.count))
        }
        guard smoothed else { return raw }
        // The result must remain a running total: starting at zero, never falling, and ending on the mean.
        // So the drinks are spread over a few hours and re-accumulated, then scaled to preserve the total.
        // Blurring the curve itself would drag its ends inwards.
        var previous = 0.0
        let pours = raw.map { point -> Double in
            defer { previous = point.units }
            return point.units - previous
        }
        let week = pours.reduce(0, +)
        guard week > 0 else { return raw }
        // Twelve quarter-hours either side, applied twice, so the kernel tapers at the edges instead of
        // cutting off as a single box pass would.
        let span = 12
        let blur = { (xs: [Double]) in
            xs.indices.map { i in
                (max(0, i - span)...min(xs.count - 1, i + span)).reduce(0) { $0 + xs[$1] } / Double(2 * span + 1)
            }
        }
        let spread = blur(blur(pours))
        // The blur pushes a little past the end of the day, where it is lost; scaling restores it.
        let scale = week / spread.reduce(0, +)
        var running = 0.0
        return zip(raw, spread).map { point, poured in
            running += poured * scale
            return CurvePoint(x: point.x, units: running)
        }
    }
}
