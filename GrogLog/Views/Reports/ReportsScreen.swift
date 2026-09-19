import Charts
import SwiftUI

struct ReportsScreen: View {
    let ledger: Ledger
    @Environment(Prefs.self) private var prefs
    @State private var weeks = 12
    @State private var settingGoal = false

    var body: some View {
        let clock = ledger.clock
        let today = ledger.today
        let thisWeek = clock.weekStart(of: today)
        let stats = (0..<weeks).reversed().map { ledger.week(starting: thisWeek - 7 * $0, goal: prefs.goal) }
        let days = max(stats[0].start, ledger.firstDay ?? today)...today

        ScrollView {
            VStack(spacing: 16) {
                MonthlyProgressCard(ledger: ledger, goal: prefs.goal) { settingGoal = true }
                MonthCard(ledger: ledger)
                WeeksCard(stats: stats, weeks: $weeks)
                SummaryTiles(ledger: ledger, stats: stats, days: days, currency: prefs.currency)
                WeekdayCard(ledger: ledger, days: days)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Reports")
        .toolbar {
            Button(prefs.goal.isEnabled ? "Goal" : "Set a goal", systemImage: "target") { settingGoal = true }
                .labelStyle(.titleAndIcon)
        }
        .sheet(isPresented: $settingGoal) { GoalSheet() }
    }
}

/// The last four weeks as two trend lines — what you drank and your budget, each a 7-day rolling average so the
/// direction shows through the day-to-day noise — with the budget's taper over the fortnight ahead.
private struct MonthlyProgressCard: View {
    let ledger: Ledger
    let goal: Goal
    let onSetGoal: () -> Void

    var body: some View {
        let calendar = ledger.clock.calendar
        let today = ledger.today
        let past = (today - 27)...today
        let budgets = Dictionary(((today - 33)...(today + 14)).compactMap { day in ledger.dailyBudget(on: day, goal: goal).map { (day, $0) } }, uniquingKeysWith: { a, _ in a })
        let averageBudget = { (day: DayKey) -> Double? in
            let values = ((day - 6)...day).compactMap { budgets[$0] }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let drank = past.compactMap { day in averageDrank(day).map { (day.date(in: calendar), $0) } }
        // Fixed schedule: one budget series, averaged like your drinking, solid to today and dashed after.
        // Dynamic: past budgets just echo your own drinking, so only the plan is drawn — today's budget if kept to.
        let budget = goal.isDynamic ? [] : past.compactMap { day in averageBudget(day).map { (day.date(in: calendar), $0) } }
        let plan = (today...(today + 14)).compactMap { day in
            (goal.isDynamic ? budgets[day] : averageBudget(day)).map { (day.date(in: calendar), $0) }
        }

        Card(title: "Monthly progress") {
            if let todays = ledger.dailyBudget(on: today, goal: goal) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's budget \(todays.unitsText) u")
                    if let stop = ledger.projection(goal: goal).underOneUnit {
                        Text("Under 1 u/day by \(stop.date(in: calendar).formatted(date: .abbreviated, time: .omitted)) at this rate")
                            .foregroundStyle(Color.dry)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(budget, id: \.0) { day, units in
                    LineMark(x: .value("Day", day, unit: .day), y: .value("Units", units), series: .value("Line", "Budget"))
                        .foregroundStyle(Color.dry)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                ForEach(plan, id: \.0) { day, units in
                    LineMark(x: .value("Day", day, unit: .day), y: .value("Units", units), series: .value("Line", "Plan"))
                        .foregroundStyle(Color.dry)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                        .interpolationMethod(.monotone)
                }
                ForEach(drank, id: \.0) { day, units in
                    AreaMark(x: .value("Day", day, unit: .day), y: .value("Units", units), series: .value("Line", "Drank"))
                        .foregroundStyle(LinearGradient(colors: [Color.grog.opacity(0.3), Color.grog.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", day, unit: .day), y: .value("Units", units), series: .value("Line", "Drank"))
                        .foregroundStyle(Color.grog)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
            }
            .frame(height: 220)

            HStack(spacing: 16) {
                LegendKey(label: "Drank", color: .grog)
                if goal.isEnabled {
                    if !goal.isDynamic { LegendKey(label: "Budget", color: .dry) }
                    LegendKey(label: goal.isDynamic ? "Plan, if kept to" : "Plan", color: .dry, dashed: true)
                }
                Spacer()
                Text("7-day averages").font(.caption).foregroundStyle(.tertiary)
            }
            if !goal.isEnabled {
                Button("Set a goal to see your budget come down", systemImage: "target", action: onSetGoal)
                    .font(.subheadline)
            }
        }
    }

    /// Mean units over the logged days in the week ending `day` (today counts once it has drinks). Nil when none.
    private func averageDrank(_ day: DayKey) -> Double? {
        let values = ((day - 6)...day).filter(ledger.isLogged).map { ledger.totals(on: $0).units }
        guard !values.isEmpty, ledger.status(on: day) != .today else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

/// This month's running total against last month's, Strava-style.
private struct MonthCard: View {
    let ledger: Ledger

    var body: some View {
        let calendar = ledger.clock.calendar
        let today = ledger.today
        let thisMonth = today.monthStart
        let lastMonth = (thisMonth - 1).monthStart
        let current = ledger.monthCumulative(thisMonth, through: today)
        let previous = ledger.monthCumulative(lastMonth)
        let dayOfMonth = today.components.day
        let lastAtSameDay = previous[min(dayOfMonth, previous.count - 1)].units
        let now = current.last?.units ?? 0
        let hasLastMonth = (previous.last?.units ?? 0) > 0

        Card(title: "This month") {
            HStack(alignment: .firstTextBaseline) {
                Text(now.unitsText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("units").foregroundStyle(.secondary)
                Spacer()
                if lastAtSameDay > 0 {
                    let change = (now - lastAtSameDay) / lastAtSameDay
                    Label(change.formatted(.percent.precision(.fractionLength(0))), systemImage: change <= 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.headline)
                        .foregroundStyle(change <= 0 ? Color.dry : Color.over)
                }
            }
            if hasLastMonth {
                Text("Last month by day \(dayOfMonth): \(lastAtSameDay.unitsText) u")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(hasLastMonth ? previous : []) {
                    LineMark(x: .value("Day", $0.hour), y: .value("Units", $0.units), series: .value("Month", "Last"))
                        .foregroundStyle(Color.gray.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(current) {
                    AreaMark(x: .value("Day", $0.hour), yStart: .value("Units", 0), yEnd: .value("Units", $0.units))
                        .foregroundStyle(LinearGradient(colors: [Color.grog.opacity(0.35), Color.grog.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Day", $0.hour), y: .value("Units", $0.units), series: .value("Month", "This"))
                        .foregroundStyle(Color.grog)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                if let last = current.last {
                    PointMark(x: .value("Day", last.hour), y: .value("Units", last.units))
                        .foregroundStyle(Color.grog)
                        .symbolSize(80)
                }
            }
            .chartXScale(domain: 0...31)
            .chartXAxis {
                AxisMarks(values: [1, 8, 15, 22, 29]) { AxisGridLine(); AxisValueLabel() }
            }
            .frame(height: 200)

            HStack(spacing: 16) {
                LegendKey(label: thisMonth.date(in: calendar).formatted(.dateTime.month(.wide)), color: .grog)
                if hasLastMonth {
                    LegendKey(label: lastMonth.date(in: calendar).formatted(.dateTime.month(.wide)), color: .gray.opacity(0.6))
                }
            }
        }
    }
}

/// Weekly units as bars against the tapering budget.
private struct WeeksCard: View {
    let stats: [WeekStat]
    @Binding var weeks: Int
    @Environment(Prefs.self) private var prefs

    var body: some View {
        let calendar = prefs.clock.calendar
        Card(title: "Weekly") {
            Picker("Range", selection: $weeks) {
                Text("8 weeks").tag(8)
                Text("12 weeks").tag(12)
                Text("6 months").tag(26)
                Text("1 year").tag(52)
            }
            .pickerStyle(.segmented)

            Chart {
                ForEach(stats) { week in
                    BarMark(x: .value("Week", week.start.date(in: calendar), unit: .weekOfYear), y: .value("Units", week.totals.units))
                        .foregroundStyle(week.budget.map { week.totals.units > $0 } == true ? Color.over.gradient : Color.grog.gradient)
                        .clipShape(.rect(cornerRadius: 4))
                }
                ForEach(stats.filter { $0.budget != nil }) { week in
                    LineMark(x: .value("Week", week.start.date(in: calendar), unit: .weekOfYear), y: .value("Budget", week.budget!))
                        .interpolationMethod(.stepCenter)
                        .foregroundStyle(Color.dry)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                RuleMark(y: .value("Guideline", Units.weeklyGuideline))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("14 u guideline").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .frame(height: 220)

            HStack(spacing: 16) {
                LegendKey(label: "Units", color: .grog)
                LegendKey(label: "Budget", color: .dry)
            }
        }
    }
}

private struct SummaryTiles: View {
    let ledger: Ledger
    let stats: [WeekStat]
    let days: ClosedRange<DayKey>
    let currency: String

    var body: some View {
        let totals = stats.reduce(into: DayTotals()) { sum, week in
            sum.units += week.totals.units
            sum.kcal += week.totals.kcal
            sum.cost += week.totals.cost
        }
        let dry = stats.reduce(0) { $0 + $1.dryDays }
        let unlogged = stats.reduce(0) { $0 + $1.unloggedDays }
        let fullWeeks = stats.dropLast().filter { $0.unloggedDays < 7 }
        let average = fullWeeks.isEmpty ? nil : fullWeeks.reduce(0) { $0 + $1.totals.units } / Double(fullWeeks.count)

        LazyVGrid(columns: [GridItem(spacing: 12), GridItem(spacing: 12)], spacing: 12) {
            Tile(title: "Average week", value: average.map { "\($0.unitsText) u" } ?? "—")
            Tile(title: "Dry streak", value: "\(ledger.dryStreak()) days", detail: "Best \(ledger.longestDryStreak(in: days))", tint: .dry)
            Tile(title: "Dry days", value: "\(dry) of \(days.count)", tint: .dry)
            Tile(title: "Not logged", value: "\(unlogged) days", detail: unlogged > 0 ? "Fill these in from Calendar" : nil)
            Tile(title: "Spent", value: totals.cost.money(currency))
            Tile(title: "Calories", value: totals.kcal.kcalText, detail: "≈ \(Int(totals.kcal / 250)) burgers")
        }
    }
}

private struct Tile: View {
    let title: String
    let value: String
    var detail: String?
    var tint = Color.primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

/// Which nights do the damage: average units per weekday across logged days.
private struct WeekdayCard: View {
    let ledger: Ledger
    let days: ClosedRange<DayKey>

    var body: some View {
        let calendar = ledger.clock.calendar
        let byWeekday = Dictionary(grouping: days.filter(ledger.isLogged), by: \.weekday)
        let order = (0..<7).map { ($0 + calendar.firstWeekday - 1) % 7 + 1 }
        let symbols = calendar.shortWeekdaySymbols

        Card(title: "By weekday") {
            Chart {
                ForEach(order, id: \.self) { weekday in
                    let days = byWeekday[weekday] ?? []
                    let average = days.isEmpty ? 0 : days.reduce(0) { $0 + ledger.totals(on: $1).units } / Double(days.count)
                    BarMark(x: .value("Day", symbols[weekday - 1]), y: .value("Units", average))
                        .foregroundStyle(Color.grog.gradient)
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
            .frame(height: 160)
        }
    }
}
