import GRDBQuery
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
        let firstWeek = min(clock.weekStart(of: ledger.firstDay ?? today), thisWeek - 7 * (weeks - 1))
        let stats = stride(from: firstWeek.number, through: thisWeek.number, by: 7).map { ledger.week(starting: DayKey(number: $0), goal: prefs.goal) }
        let shown = stats.suffix(weeks)
        let days = max(shown[shown.startIndex].start, ledger.firstDay ?? today)...today

        ScrollView {
            VStack(spacing: 16) {
                MonthlyProgressCard(ledger: ledger, goal: prefs.goal) { settingGoal = true }
                WeekCard(ledger: ledger, goal: prefs.goal)
                MonthCard(ledger: ledger)
                WeeksCard(stats: stats, weeks: $weeks)
                SummaryTiles(ledger: ledger, stats: Array(shown), days: days, currency: prefs.currency)
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
/// Drinking against the budget: the orange line is units drunk in the last 24 hours at any moment, so each night is
/// a hump you can compare with that day's budget, which runs on as the dashed plan from today.
private struct MonthlyProgressCard: View {
    let ledger: Ledger
    let goal: Goal
    let onSetGoal: () -> Void
    @Query<EntriesRequest> private var entries: [Entry]

    /// As far back as the chart scrolls; the drinks themselves are only fetched for this window.
    private static let history = 120
    /// Days across, pinchable between a week and the lot.
    @State private var window = 35.0
    @GestureState private var pinch = 1.0

    init(ledger: Ledger, goal: Goal, onSetGoal: @escaping () -> Void) {
        self.ledger = ledger
        self.goal = goal
        self.onSetGoal = onSetGoal
        _entries = Query(constant: EntriesRequest(days: (ledger.today - Self.history - 1)...ledger.today))
    }

    var body: some View {
        let calendar = ledger.clock.calendar
        let today = ledger.today
        // The whole history is drawn; the chart shows a month of it at a time and scrolls back through the rest.
        let history = max(ledger.firstDay ?? today - 27, today - Self.history)
        // Never show more days than there are; a window wider than the data leaves it stranded at the left.
        let days = min(Int((window / pinch).rounded()), history.distance(to: today + 15))
        let past = history...today
        let drank = ledger.rollingDay(entries, over: past)
        let budgets = { (days: ClosedRange<DayKey>) in days.compactMap { day in ledger.dailyBudget(on: day, goal: goal).map { (day, $0) } } }
        let behind = goal.isEnabled ? budgets(past) : []
        let ahead = goal.isEnabled ? budgets(today...(today + 14)).map { ($0.0.date(in: calendar), $0.1) } : []
        // Scale to the window in view, so an old binge doesn't flatten the recent weeks.
        let shown = drank.filter { $0.date >= ledger.clock.start(of: today - days) }
        let top = max(10, shown.map(\.units).max() ?? 0, ahead.map(\.1).max() ?? 0) * 1.15

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
                ForEach(drank, id: \.date) { point in
                    AreaMark(x: .value("When", point.date), y: .value("Units", point.units), series: .value("Line", "Drank"))
                        .foregroundStyle(LinearGradient(colors: [Color.grog.opacity(0.3), Color.grog.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("When", point.date), y: .value("Units", point.units), series: .value("Line", "Drank"))
                        .foregroundStyle(Color.grog)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                ForEach(behind, id: \.0) { day, units in
                    LineMark(x: .value("Day", day.date(in: calendar)), y: .value("Units", units), series: .value("Line", "Budget"))
                        .foregroundStyle(Color.dry)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                ForEach(ahead, id: \.0) { day, units in
                    LineMark(x: .value("Day", day), y: .value("Units", units), series: .value("Line", "Ahead"))
                        .foregroundStyle(Color.dry)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                        .interpolationMethod(.monotone)
                }
                // Today's band: drawn over the data in plain grey so it mutes rather than tints.
                let noon = today.date(in: calendar).addingTimeInterval(12 * 3600)
                RectangleMark(xStart: .value("From", noon.addingTimeInterval(-12 * 3600)), xEnd: .value("To", noon.addingTimeInterval(12 * 3600)))
                    .foregroundStyle(.gray.opacity(0.18))
            }
            .chartYScale(domain: 0...top)
            .clipped()
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: max(1, days / 5))) { AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: Double(days) * 86_400)
            .chartScrollPosition(initialX: (today - (days - 4)).date(in: calendar))
            .frame(height: 220)
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, pinch, _ in pinch = min(5, max(0.2, value.magnification)) }
                    .onEnded { value in
                        window = min(Double(Self.history), max(7, (window / min(5, max(0.2, value.magnification))).rounded()))
                    }
            )

            HStack(spacing: 16) {
                LegendKey(label: "Last 24h", color: .grog)
                if goal.isEnabled {
                    LegendKey(label: "Budget", color: .dry)
                    LegendKey(label: "Plan", color: .dry, dashed: true)
                }
            }
            if !goal.isEnabled {
                Button("Set a goal to see your budget come down", systemImage: "target", action: onSetGoal)
                    .font(.subheadline)
            }
        }
    }
}

/// This week's running total against the last few weeks, with the week's budget as a dashed line.
private struct WeekCard: View {
    let ledger: Ledger
    let goal: Goal
    @Query<EntriesRequest> private var entries: [Entry]

    init(ledger: Ledger, goal: Goal) {
        self.ledger = ledger
        self.goal = goal
        let start = ledger.clock.weekStart(of: ledger.today)
        _entries = Query(constant: EntriesRequest(days: (start - 21)...ledger.today))
    }

    var body: some View {
        let clock = ledger.clock
        let today = ledger.today
        let start = clock.weekStart(of: today)
        let current = ledger.weekCurve(entries, of: start, through: today)
        let earlier = (1...3).map { ledger.weekCurve(entries, of: start - 7 * $0) }.filter { $0.count > 1 }
        let budget = goal.isEnabled ? ledger.weekBudgetCurve(of: start, goal: goal) : []
        let into = Double(start.distance(to: today)) + min(1, clock.hours(.now, into: today) / 24)
        let lastWeek = earlier.first?.last { $0.hour <= into }?.units
        let now = current.last?.units ?? 0

        Card(title: "This week") {
            HStack(alignment: .firstTextBaseline) {
                Text(now.unitsText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("units").foregroundStyle(.secondary)
                Spacer()
                if let lastWeek, lastWeek > 0 {
                    let change = (now - lastWeek) / lastWeek
                    Label(change.formatted(.percent.precision(.fractionLength(0))), systemImage: change <= 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.headline)
                        .foregroundStyle(change <= 0 ? Color.dry : Color.over)
                }
            }
            if let lastWeek {
                Text("Last week by now: \(lastWeek.unitsText) u")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(Array(earlier.enumerated()), id: \.offset) { index, week in
                    ForEach(week) { point in
                        LineMark(x: .value("Day", point.hour), y: .value("Units", point.units), series: .value("Week", "-\(index + 1)"))
                            .foregroundStyle(Color.gray.opacity(0.5 - Double(index) * 0.12))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                ForEach(budget) { point in
                    LineMark(x: .value("Day", point.hour), y: .value("Units", point.units), series: .value("Week", "budget"))
                        .foregroundStyle(Color.dry)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                }
                ForEach(current) { point in
                    AreaMark(x: .value("Day", point.hour), yStart: .value("Units", 0), yEnd: .value("Units", point.units))
                        .foregroundStyle(LinearGradient(colors: [Color.grog.opacity(0.3), Color.grog.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Day", point.hour), y: .value("Units", point.units), series: .value("Week", "this"))
                        .foregroundStyle(Color.grog)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                if let last = current.last {
                    PointMark(x: .value("Day", last.hour), y: .value("Units", last.units))
                        .foregroundStyle(Color.grog)
                        .symbolSize(80)
                }
            }
            .chartXScale(domain: 0...7)
            .chartXAxis {
                AxisMarks(values: Array(0...6).map(Double.init)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        Text((start + Int(value.as(Double.self) ?? 0)).date(in: clock.calendar).formatted(.dateTime.weekday(.abbreviated)))
                    }
                }
            }
            .frame(height: 200)

            HStack(spacing: 16) {
                LegendKey(label: "This week", color: .grog)
                LegendKey(label: "Earlier weeks", color: .gray.opacity(0.5))
                if !budget.isEmpty { LegendKey(label: "Budget", color: .dry, dashed: true) }
            }
        }
    }
}

/// This month's running total against last month's, Strava-style.
private struct MonthCard: View {
    let ledger: Ledger
    @Query<EntriesRequest> private var entries: [Entry]

    init(ledger: Ledger) {
        self.ledger = ledger
        _entries = Query(constant: EntriesRequest(days: (ledger.today.monthStart - 1).monthStart...ledger.today))
    }

    var body: some View {
        let calendar = ledger.clock.calendar
        let today = ledger.today
        let thisMonth = today.monthStart
        let lastMonth = (thisMonth - 1).monthStart
        let current = ledger.monthCurve(entries, of: thisMonth, through: today)
        let previous = ledger.monthCurve(entries, of: lastMonth)
        let dayOfMonth = today.components.day
        let lastAtSameDay = previous.last { $0.hour <= Double(dayOfMonth) }?.units ?? 0
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
                RectangleMark(xStart: .value("From", Double(dayOfMonth) - 0.5), xEnd: .value("To", Double(dayOfMonth) + 0.5))
                    .foregroundStyle(.gray.opacity(0.18))
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
                if let thisWeek = stats.last?.start.date(in: calendar) {
                    RectangleMark(xStart: .value("From", thisWeek.addingTimeInterval(-12 * 3600)), xEnd: .value("To", thisWeek.addingTimeInterval(6.5 * 24 * 3600)))
                        .foregroundStyle(.gray.opacity(0.18))
                }
                RuleMark(y: .value("Guideline", Units.weeklyGuideline))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("14 u guideline").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: Double(weeks) * 7 * 86_400)
            .chartScrollPosition(initialX: (stats.last!.start - 7 * (weeks - 1)).date(in: prefs.clock.calendar))
            .frame(height: 220)

            HStack(spacing: 16) {
                LegendKey(label: "Units", color: .grog)
                LegendKey(label: "Budget", color: .dry)
                Spacer()
                Text("scroll back").font(.caption).foregroundStyle(.tertiary)
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
                        .foregroundStyle(Color.grog.opacity(weekday == ledger.today.weekday ? 1 : 0.45).gradient)
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
            .frame(height: 160)
        }
    }
}
