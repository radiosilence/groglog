import Charts
import SwiftUI

struct ReportsScreen: View {
    let ledger: Ledger
    @Environment(Prefs.self) private var prefs
    @State private var weeks = 12
    @State private var settingGoal = false

    var body: some View {
        let clock = ledger.clock
        let today = clock.today
        let thisWeek = clock.weekStart(of: today)
        let stats = (0..<weeks).reversed().map { ledger.week(starting: clock.adding(-7 * $0, to: thisWeek), goal: prefs.goal) }
        let days = ledger.days(from: max(stats[0].start, ledger.firstDay ?? today), through: today)

        ScrollView {
            VStack(spacing: 16) {
                BurndownCard(ledger: ledger, goal: prefs.goal) { settingGoal = true }
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

/// Daily units as bars against the budget line coming down, with the fortnight ahead.
private struct BurndownCard: View {
    let ledger: Ledger
    let goal: Goal
    let onSetGoal: () -> Void

    var body: some View {
        let clock = ledger.clock
        let today = clock.today
        let past = ledger.days(from: clock.adding(-27, to: today), through: today)
        let ahead = goal.isEnabled ? ledger.days(from: today, through: clock.adding(14, to: today)) : []

        Card(title: "Burndown") {
            if let budget = ledger.dailyBudget(on: today, goal: goal) {
                Text("Today's budget \(budget.unitsText) u")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(past, id: \.self) { day in
                    let units = ledger.totals(on: day).units
                    BarMark(x: .value("Day", day, unit: .day), y: .value("Units", units))
                        .foregroundStyle(Color.heat(units: units, budget: ledger.dailyBudget(on: day, goal: goal)).gradient)
                        .clipShape(.rect(cornerRadius: 3))
                }
                ForEach(past, id: \.self) { day in
                    if let budget = ledger.dailyBudget(on: day, goal: goal) {
                        LineMark(x: .value("Day", day, unit: .day), y: .value("Budget", budget), series: .value("Line", "Budget"))
                            .foregroundStyle(Color.dry)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                }
                ForEach(ahead, id: \.self) { day in
                    if let budget = ledger.dailyBudget(on: day, goal: goal) {
                        LineMark(x: .value("Day", day, unit: .day), y: .value("Budget", budget), series: .value("Line", "Ahead"))
                            .foregroundStyle(Color.dry.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
            }
            .frame(height: 220)

            if goal.isEnabled {
                HStack(spacing: 16) {
                    LegendKey(label: "Units", color: .grog)
                    LegendKey(label: "Budget", color: .dry)
                    LegendKey(label: "Ahead", color: .dry, dashed: true)
                }
            } else {
                Button("Set a goal to see your budget come down", systemImage: "target", action: onSetGoal)
                    .font(.subheadline)
            }
        }
    }
}

/// This month's running total against last month's, Strava-style.
private struct MonthCard: View {
    let ledger: Ledger

    var body: some View {
        let clock = ledger.clock
        let calendar = clock.calendar
        let today = clock.today
        let thisMonth = calendar.dateInterval(of: .month, for: today)!.start
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth)!
        let current = ledger.monthCumulative(thisMonth, through: today)
        let previous = ledger.monthCumulative(lastMonth)
        let dayOfMonth = calendar.component(.day, from: today)
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
                LegendKey(label: thisMonth.formatted(.dateTime.month(.wide)), color: .grog)
                if hasLastMonth {
                    LegendKey(label: lastMonth.formatted(.dateTime.month(.wide)), color: .gray.opacity(0.6))
                }
            }
        }
    }
}

/// Weekly units as bars against the tapering budget.
private struct WeeksCard: View {
    let stats: [WeekStat]
    @Binding var weeks: Int

    var body: some View {
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
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Units", week.totals.units))
                        .foregroundStyle(week.budget.map { week.totals.units > $0 } == true ? Color.over.gradient : Color.grog.gradient)
                        .clipShape(.rect(cornerRadius: 4))
                }
                ForEach(stats.filter { $0.budget != nil }) { week in
                    LineMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Budget", week.budget!))
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
    let days: [Date]
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
    let days: [Date]

    var body: some View {
        let calendar = ledger.clock.calendar
        let logged = days.filter { [.drank, .alcoholFree].contains(ledger.status(on: $0)) }
        let byWeekday = Dictionary(grouping: logged) { calendar.component(.weekday, from: $0) }
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
