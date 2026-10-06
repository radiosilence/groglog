import GRDBQuery
import Charts
import SwiftUI

struct ReportsScreen: View {
    let ledger: Ledger
    @Environment(Prefs.self) private var prefs
    @State private var weeks = 12
    @State private var settingGoal = false
    @State private var nights = Nights(byDay: [:])
    @AppStorage("demoMode") private var demoMode = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let clock = ledger.clock
        let today = ledger.today
        let thisWeek = clock.weekStart(of: today)
        // Back to the first heart reading as well, so the line carries on from before the log began.
        let firstWeek = min(clock.weekStart(of: [ledger.firstDay, nights.first].compactMap(\.self).min() ?? today), thisWeek - 7 * (weeks - 1))
        let stats = stride(from: firstWeek.number, through: thisWeek.number, by: 7).map { ledger.week(starting: DayKey(number: $0), goal: prefs.goal) }
        let shown = stats.suffix(weeks)
        let days = min(max(shown[shown.startIndex].start, ledger.firstDay ?? today), today)...today

        ScrollView {
            VStack(spacing: 16) {
                ProgressCard(title: "Weekly progress", days: 10, history: 60, ledger: ledger, goal: prefs.goal, nights: nights, heart: .nightly) { settingGoal = true }
                ProgressCard(title: "Monthly progress", days: 35, history: 120, ledger: ledger, goal: prefs.goal, nights: nights, heart: .averaged) { settingGoal = true }
                if nights.byDay.values.contains(where: { $0.sleep != nil }) {
                    SleepCard(ledger: ledger, nights: nights)
                }
                WeekCard(ledger: ledger, goal: prefs.goal)
                MonthCard(ledger: ledger)
                WeeksCard(stats: stats, nights: nights, weeks: $weeks)
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
        .sheet(isPresented: $settingGoal) { GoalSheet(goal: prefs.goal) }
        // Again on coming back: the watch syncs last night some time after the app was last open.
        .task(id: [today.number, prefs.readsHeart ? 1 : 0, prefs.readsSleep ? 1 : 0, demoMode ? 1 : 0, scenePhase == .active ? 1 : 0]) {
            guard scenePhase == .active else { return }
            #if DEBUG
            if demoMode { nights = Seed.nights(ledger); return }
            #endif
            nights = await Health.shared.nights(clock: clock, heart: prefs.readsHeart, sleep: prefs.readsSleep)
        }
    }
}

/// Which heart readings a progress chart carries: each night as it came, or the week around it.
private enum HeartLines {
    case nightly, averaged
}

private enum HeartReading: String, CaseIterable {
    case hrv = "HRV", resting = "Resting HR", sleeping = "Asleep HR"

    var color: Color {
        switch self {
        case .hrv: .hrv
        case .resting: .pulse
        case .sleeping: .sleeping
        }
    }

    var value: KeyPath<Night, Double?> {
        switch self {
        case .hrv: \.hrv
        case .resting: \.restingHR
        case .sleeping: \.sleepingHR
        }
    }

    var unit: String { self == .hrv ? "ms" : "bpm" }

    var short: String {
        switch self {
        case .hrv: "HRV"
        case .resting: "RHR"
        case .sleeping: "Asleep"
        }
    }

    /// HRV falls after a heavy night; heart rate rises.
    func isWorse(_ change: Double) -> Bool { self == .hrv ? change < 0 : change > 0 }
}

private struct HeartPoint: Equatable, Identifiable {
    let date: Date
    let value: Double
    let reading: HeartReading
    /// A run of consecutive readings; a missing night starts a new one.
    let run: Int
    /// Alone in its run, so there is no line to draw it with.
    var alone = false
    /// One end of a dashed line across nights with no reading. It joins what was measured either side of the gap and
    /// claims nothing about what is in it.
    var bridge = false
    var id: String { "\(series)@\(date.timeIntervalSinceReferenceDate)" }
    var series: String { "\(reading.rawValue)\(bridge ? "~" : "")\(run)" }

    /// `before` is the last reading ahead of the first day, however old, so a line that went quiet before the chart
    /// begins still comes in from the left rather than starting cold. Its end is cut to the first day, on the same
    /// slope: a point months outside the chart is still data to it, and it scrolls there.
    static func line(_ reading: HeartReading, _ days: [DayKey], before: DayKey? = nil, at date: (DayKey) -> Date, value: (DayKey) -> Double?) -> [HeartPoint] {
        var run = 0
        var points = days.compactMap { day -> HeartPoint? in
            guard let value = value(day) else { run += 1; return nil }
            return HeartPoint(date: date(day), value: value, reading: reading, run: run)
        }
        let sizes = Dictionary(grouping: points, by: \.run).mapValues(\.count)
        for i in points.indices { points[i].alone = sizes[points[i].run] == 1 }
        let anchor = before.flatMap { day -> HeartPoint? in
            guard let then = value(day), let next = points.first, let edge = days.first.map(date) else { return nil }
            let from = date(day)
            let value = then + (next.value - then) * edge.timeIntervalSince(from) / next.date.timeIntervalSince(from)
            return HeartPoint(date: edge, value: value, reading: reading, run: -1)
        }
        let ends = ([anchor].compactMap(\.self) + points)
        let bridges = zip(ends, ends.dropFirst()).enumerated().flatMap { index, pair -> [HeartPoint] in
            guard pair.0.run != pair.1.run else { return [] }
            return [pair.0, pair.1].map { HeartPoint(date: $0.date, value: $0.value, reading: reading, run: index, bridge: true) }
        }
        return points + bridges
    }
}

/// One heart reading laid over a units chart, fitted to its height with its own axis down the trailing edge, in the
/// reading's colour. One at a time: HRV in ms and heart rate in bpm on a shared scale left each a thin band.
private struct HeartScale: Equatable {
    let low: Double
    let high: Double
    let top: Double
    let color: Color

    init?(_ points: [HeartPoint], top: Double) {
        guard let lo = points.map(\.value).min(), let hi = points.map(\.value).max(), let reading = points.first?.reading else { return nil }
        color = reading.color
        low = (lo / 5).rounded(.down) * 5 - 5
        high = max(low + 20, (hi / 5).rounded(.up) * 5 + 5)
        self.top = top
    }

    func y(_ value: Double) -> Double { top * (0.08 + 0.84 * (value - low) / (high - low)) }

    func value(atY y: Double) -> Double { low + (y / top - 0.08) / 0.84 * (high - low) }

    var ticks: [Double] {
        let step = high - low > 60 ? 20.0 : 10.0
        return Array(stride(from: (low / step).rounded(.up) * step, through: high, by: step)).map(y)
    }

    var axis: some AxisContent {
        AxisMarks(position: .trailing, values: ticks) { value in
            AxisValueLabel { Text("\(Int(self.value(atY: value.as(Double.self) ?? 0).rounded()))").foregroundStyle(color) }
        }
    }
}

/// The heart readings a chart has, as chips in each reading's colour that choose which one it draws, on their own
/// row below the drinking keys. The choice is shared by every chart.
private struct HeartLegend: View {
    let points: [HeartPoint]
    let suffix: String
    @Binding var shown: HeartReading

    /// The chosen reading, or the first there is when the chosen one has no data in this chart.
    static func drawn(_ shown: HeartReading, in points: [HeartPoint]) -> HeartReading? {
        let readings = Set(points.map(\.reading))
        return readings.contains(shown) ? shown : HeartReading.allCases.first(where: readings.contains)
    }

    var body: some View {
        let readings = HeartReading.allCases.filter { reading in points.contains { $0.reading == reading } }
        if let drawn = Self.drawn(shown, in: points) {
            HStack(spacing: 12) {
                ChipRow(options: readings, selection: Binding(get: { drawn }, set: { shown = $0 }), tint: \.color) { "\($0.short)\(suffix)" }
                    .controlSize(.small)
                Text(drawn.unit).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

/// What was drunk each day as bars, against the daily budget as a line that runs on from today as the
/// dashed plan. Both are the days themselves: nothing here is averaged.
private struct ProgressCard: View {
    let title: String
    /// As far back as the chart scrolls; the drinks themselves are only fetched for this window.
    let history: Int
    let ledger: Ledger
    let goal: Goal
    let nights: Nights
    let heart: HeartLines
    let onSetGoal: () -> Void
    /// Days across, pinchable between a few days and the lot.
    @State private var window: Double
    @AppStorage("chartHeartReading") private var shownHeart = HeartReading.hrv
    @GestureState private var pinch = 1.0
    /// Held here rather than passed to the chart once: the chart is redrawn every minute for the "now" rule, and one
    /// given only a starting position returns to the start of its range each time.
    @State private var scrolledTo: Date?

    init(title: String, days: Double, history: Int, ledger: Ledger, goal: Goal, nights: Nights, heart: HeartLines, onSetGoal: @escaping () -> Void) {
        self.title = title
        self.history = history
        self.ledger = ledger
        self.goal = goal
        self.nights = nights
        self.heart = heart
        self.onSetGoal = onSetGoal
        _window = State(initialValue: days)
    }

    var body: some View {
        let calendar = ledger.clock.calendar
        let today = ledger.today
        // Everything back to `history` days is drawn; the chart shows a window of it and scrolls through the rest.
        // The log's own history only: older heart readings come in from the left edge on a dash, and widening the
        // chart to reach them would leave months of it empty.
        let start = min(max(ledger.firstDay ?? today - 27, today - history), today)
        // Never show more days than there are; a window wider than the data leaves it stranded at the left.
        let days = min(Int((window / pinch).rounded()), start.distance(to: today + 15))
        let past = start...today
        // To the minute, so the chart's inputs read the same from one commit to the next and it is not laid out
        // again for a rule that has not visibly moved.
        let now = Date(timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        let noon = { (day: DayKey) in day.date(in: calendar).addingTimeInterval(12 * 3600) }
        // What was drunk is a bar over its own day rather than a line through it: a day's drinking is a
        // quantity, and a mean of the surrounding days can read 25 on a day of 16. Each bar is coloured
        // against that day's own budget, so it matches its calendar tile.
        let sofar = ledger.totals(on: today).units
        let drank = past.compactMap { day -> DayBar? in
            let noon = day.date(in: calendar).addingTimeInterval(12 * 3600)
            let heat = { Color.heat(units: $0, budget: ledger.dailyBudget(on: day, goal: goal)) }
            if day == today { return DayBar(date: noon, units: sofar, partial: true, heat: heat(sofar)) }
            guard ledger.isLogged(day) else { return nil }
            let units = ledger.totals(on: day).units
            return DayBar(date: noon, units: units, partial: false, heat: heat(units))
        }
        // Every day's budget sits at its own noon, so each day's decay spans the same width. Placing today's
        // point on the "now" rule would stretch the segment before it and squash the one after, each still
        // carrying a day's cut, so the line would kink at today, more sharply as the day went on. The rule is
        // met by a point interpolated along the line instead. Unsmoothed: a scheduled taper is already a smooth
        // curve, and a dynamic one steps because the drinking does.
        let curve = (start...(today + 14)).compactMap { day in
            ledger.dailyBudget(on: day, goal: goal).map { BudgetPoint(date: noon(day), units: $0) }
        }
        let onTheRule = { () -> BudgetPoint? in
            let day = now >= noon(today) ? today : today - 1
            guard let here = ledger.dailyBudget(on: day, goal: goal),
                  let next = ledger.dailyBudget(on: day + 1, goal: goal) else { return nil }
            return BudgetPoint(date: now, units: here + (next - here) * now.timeIntervalSince(noon(day)) / 86_400)
        }()
        let behind = curve.filter { $0.date <= now } + [onTheRule].compactMap(\.self)
        let ahead = [onTheRule].compactMap(\.self) + curve.filter { $0.date > now }
        // Scale to the window in view, so an old binge does not flatten the recent weeks.
        let shown = drank.filter { $0.date >= ledger.clock.start(of: today - days) }
        let top = max(10, sofar, shown.map(\.units).max() ?? 0, ahead.map(\.units).max() ?? 0) * 1.15
        // Each night sits on the bar of the day it followed. Averaged, it is the mean of the week up to that night,
        // shown only once enough of that week has readings.
        let nightsShown = Array(start..<today)
        let hearts = switch heart {
        case .nightly:
            HeartReading.allCases.flatMap { reading in
                HeartPoint.line(reading, nightsShown, before: nights.last(reading.value, before: start), at: noon) { nights[$0]?[keyPath: reading.value] }
            }
        case .averaged:
            // The anchor is averaged the same way, so a lone old reading with no week around it is not used.
            [HeartReading.hrv, .resting].flatMap { reading in
                HeartPoint.line(reading, nightsShown, before: nights.last(reading.value, before: start), at: noon) { nights.mean(reading.value, over: ($0 - 6)...$0) }
            }
        }

        Card(title: title) {
            VStack(alignment: .leading, spacing: 2) {
                if let todays = ledger.dailyBudget(on: today, goal: goal) {
                    Text("Today's budget \(todays.unitsText) u")
                    if let stop = ledger.projection(goal: goal).stoppable {
                        Text(stop <= today ? "Already low enough to stop" : "Low enough to stop by \(stop.date(in: calendar).formatted(date: .abbreviated, time: .omitted)) at this rate")
                            .foregroundStyle(Color.dry)
                    }
                }
                heartSummary(today - 1)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            let drawn = hearts.filter { $0.reading == HeartLegend.drawn(shownHeart, in: hearts) }
            ProgressPlot(drank: drank, behind: behind, ahead: ahead, heart: drawn, heartScale: HeartScale(drawn, top: top), dots: heart == .nightly,
                         now: now, top: top, days: days,
                         x: Binding(get: { scrolledTo ?? (today - (days - 4)).date(in: calendar) }, set: { scrolledTo = $0 }))
            // Simultaneous, or the chart's own scrolling swallows it and nothing zooms.
            .simultaneousGesture(
                MagnifyGesture(minimumScaleDelta: 0.05)
                    .updating($pinch) { value, pinch, _ in pinch = min(5, max(0.2, value.magnification)) }
                    .onEnded { value in
                        window = min(Double(history), max(4, (window / min(5, max(0.2, value.magnification))).rounded()))
                    }
            )

            HStack(spacing: 16) {
                LegendKey(label: "Drank", color: .grog, bar: true, ramp: [.dry, .grog, .over])
                if goal.isEnabled {
                    LegendKey(label: "Budget", color: .dry)
                    LegendKey(label: "Plan", color: .dry, dashed: true)
                }
            }
            HeartLegend(points: hearts, suffix: heart == .nightly ? "" : ", 7-night", shown: $shownHeart)
            if !goal.isEnabled {
                Button("Set a goal to see your budget come down", systemImage: "target", action: onSetGoal)
                    .font(.subheadline)
            }
        }
    }

    /// Last night against the week before it, to show the effect of one evening.
    @ViewBuilder private func heartSummary(_ lastNight: DayKey) -> some View {
        let week = (lastNight - 7)...(lastNight - 1)
        switch heart {
        case .nightly:
            let lines = HeartReading.allCases.compactMap { reading -> Text? in
                guard let value = nights[lastNight]?[keyPath: reading.value] else { return nil }
                let change = nights.mean(reading.value, over: week).map { value - $0 } ?? 0
                let worse = reading.isWorse(change)
                let against = Text(abs(change) < 1 ? "" : ", \(Int(abs(change).rounded())) \(change < 0 ? "under" : "over") the week before")
                    .foregroundStyle(worse ? Color.over : Color.dry)
                return Text("\(reading.short) last night \(Int(value.rounded())) \(reading.unit)\(against)")
            }
            ForEach(lines.indices, id: \.self) { lines[$0] }
        case .averaged:
            let hrv = nights.mean(\.hrv, over: (lastNight - 6)...lastNight)
            let resting = nights.mean(\.restingHR, over: (lastNight - 6)...lastNight)
            if hrv != nil || resting != nil {
                Text([hrv.map { "HRV \(Int($0.rounded())) ms" }, resting.map { "RHR \(Int($0.rounded())) bpm" }].compactMap(\.self).joined(separator: " · ") + " over the last week")
            }
        }
    }
}

private struct DayBar: Equatable {
    let date: Date
    let units: Double
    let partial: Bool
    let heat: Color
}

private struct BudgetPoint: Equatable {
    let date: Date
    let units: Double
}

/// The chart alone, on plain values, so it is laid out again only when one of them changes. Chart content is a
/// closure, which cannot be compared, so a chart built inside a card is rebuilt whenever the card is, and the
/// cards are rebuilt on every commit from any tab. The other cards' charts follow the same pattern.
private struct ProgressPlot: View, Equatable {
    let drank: [DayBar]
    let behind: [BudgetPoint]
    let ahead: [BudgetPoint]
    let heart: [HeartPoint]
    let heartScale: HeartScale?
    let dots: Bool
    let now: Date
    let top: Double
    let days: Int
    @Binding var x: Date

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.drank == rhs.drank && lhs.behind == rhs.behind && lhs.ahead == rhs.ahead && lhs.heart == rhs.heart
            && lhs.heartScale == rhs.heartScale && lhs.dots == rhs.dots && lhs.now == rhs.now && lhs.top == rhs.top && lhs.days == rhs.days
    }

    var body: some View {
        Chart {
            // Today's bar is faded: the day is not over, so the bar is not at its final height.
            ForEach(drank, id: \.date) { point in
                BarMark(x: .value("When", point.date, unit: .day), y: .value("Units", point.units))
                    .foregroundStyle(point.heat.opacity(point.partial ? 0.45 : 1))
                    .cornerRadius(3)
            }
            ForEach(behind, id: \.date) { point in
                LineMark(x: .value("Day", point.date), y: .value("Units", point.units), series: .value("Line", "Budget"))
                    .foregroundStyle(Color.dry)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            // Straight between days, like the solid half: a spline through a decaying curve leaves its
            // first point steeper than the chord, which would kink the line downwards at today.
            ForEach(ahead, id: \.date) { point in
                LineMark(x: .value("Day", point.date), y: .value("Units", point.units), series: .value("Line", "Ahead"))
                    .foregroundStyle(Color.dry)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 4]))
            }
            if let heartScale {
                ForEach(heart) { point in
                    LineMark(x: .value("Day", point.date), y: .value("Units", heartScale.y(point.value)), series: .value("Line", point.series))
                        .foregroundStyle(point.reading.color.opacity(point.bridge ? 0.6 : 1))
                        .lineStyle(StrokeStyle(lineWidth: point.bridge ? 1.5 : 2, lineCap: .round, lineJoin: .round, dash: point.bridge ? [3, 4] : []))
                    if !point.bridge, dots || point.alone {
                        PointMark(x: .value("Day", point.date), y: .value("Units", heartScale.y(point.value)))
                            .foregroundStyle(point.reading.color)
                            .symbolSize(24)
                    }
                }
            }
            RuleMark(x: .value("Today", now))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading)
            if let heartScale { heartScale.axis }
        }
        .clipped()
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, days / 5))) { AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: Double(days) * 86_400)
        .chartScrollPosition(x: $x)
        .frame(height: 220)
    }
}

/// Each night's sleep by stage, over what was drunk the evening before it.
private struct SleepCard: View {
    let ledger: Ledger
    let nights: Nights
    /// Held so a redraw does not send the chart back to the start of its range.
    @State private var scrolledTo: Date?

    var body: some View {
        let calendar = ledger.clock.calendar
        let today = ledger.today
        let slept = nights.byDay.filter { $0.value.sleep != nil }.keys
        let days = Array(max(slept.min() ?? today, today - 90)..<today)
        let noon = { (day: DayKey) in day.date(in: calendar).addingTimeInterval(12 * 3600) }
        let bars = days.flatMap { day -> [SleepBar] in
            guard let sleep = nights[day]?.sleep else { return [] }
            return [SleepBar.Stage.deep, .core, .rem, .awake].map { stage in
                let seconds = switch stage {
                case .deep: sleep.deep
                case .core: sleep.core + sleep.unstaged
                case .rem: sleep.rem
                case .awake: sleep.awake
                }
                return SleepBar(date: noon(day), stage: stage, hours: seconds / 3600)
            }
        }
        let drank = days.compactMap { day in
            ledger.isLogged(day) ? BudgetPoint(date: noon(day), units: ledger.totals(on: day).units) : nil
        }
        let lastNight = days.last { nights[$0]?.sleep != nil }

        Card(title: "Sleep") {
            if let lastNight, let sleep = nights[lastNight]?.sleep {
                summary(sleep, on: lastNight, week: (lastNight - 7)...(lastNight - 1))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            SleepPlot(bars: bars, drank: drank, x: Binding(get: { scrolledTo ?? (today - 13).date(in: calendar) }, set: { scrolledTo = $0 }))
            HStack(spacing: 12) {
                ForEach([SleepBar.Stage.deep, .core, .rem, .awake], id: \.self) { LegendKey(label: $0.label, color: $0.color, bar: true) }
                LegendKey(label: "Drank", color: .grog)
            }
            .lineLimit(1)
        }
    }

    /// Time asleep and REM against the week before. Alcohol takes REM first, so its share says more than the total.
    private func summary(_ sleep: Sleep, on night: DayKey, week: ClosedRange<DayKey>) -> some View {
        let before = week.compactMap { nights[$0]?.sleep }
        let usual = { (value: (Sleep) -> Double?) -> Double? in
            let values = before.compactMap(value)
            return values.count >= 3 ? values.mean : nil
        }
        let when = night == ledger.today - 1
            ? "Last night"
            : night.date(in: ledger.clock.calendar).formatted(.dateTime.weekday(.wide))
        let asleepChange = usual { $0.asleep }.map { sleep.asleep - $0 }
        let remChange = sleep.remShare.flatMap { share in usual { $0.remShare }.map { (share - $0) * 100 } }
        let against = { (change: Double?, text: String) -> Text in
            guard let change, text != "" else { return Text("") }
            return Text(", \(text)").foregroundStyle(change < 0 ? Color.over : Color.dry)
        }
        let asleepText = asleepChange.flatMap { abs($0) < 300 ? nil : "\(Self.duration(abs($0))) \($0 < 0 ? "less" : "more") than the week before" } ?? ""
        let remText = remChange.flatMap { abs($0) < 1 ? nil : "\(Int(abs($0).rounded())) points \($0 < 0 ? "under" : "over") the week before" } ?? ""
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(when) \(Self.duration(sleep.asleep)) asleep\(against(asleepChange, asleepText))")
            if let share = sleep.remShare {
                Text("REM \(Self.duration(sleep.rem)), \(Int((share * 100).rounded()))% of sleep\(against(remChange, remText))")
            }
        }
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) m" : "\(minutes) m"
    }
}

private struct SleepBar: Equatable {
    enum Stage {
        case deep, core, rem, awake

        var label: String {
            switch self {
            case .deep: "Deep"
            case .core: "Core"
            case .rem: "REM"
            case .awake: "Awake"
            }
        }

        var color: Color {
            switch self {
            case .deep: .deepSleep
            case .core: .coreSleep
            case .rem: .remSleep
            case .awake: .gray.opacity(0.35)
            }
        }
    }

    let date: Date
    let stage: Stage
    let hours: Double
}

private struct SleepPlot: View, Equatable {
    let bars: [SleepBar]
    let drank: [BudgetPoint]
    @Binding var x: Date

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.bars == rhs.bars && lhs.drank == rhs.drank }

    var body: some View {
        let nightly = Dictionary(grouping: bars, by: \.date).values.map { $0.map(\.hours).reduce(0, +) }
        let top = max(10, nightly.max() ?? 0) * 1.1
        // Units share the height on their own scale, read off the right-hand axis.
        let most = max(10, drank.map(\.units).max() ?? 0) * 1.1
        let y = { (units: Double) in units / most * top }
        let step = most > 60 ? 20.0 : most > 25 ? 10 : 5
        Chart {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                BarMark(x: .value("Night", bar.date, unit: .day), y: .value("Hours", bar.hours))
                    .foregroundStyle(bar.stage.color)
            }
            ForEach(drank, id: \.date) { point in
                LineMark(x: .value("Night", point.date), y: .value("Hours", y(point.units)), series: .value("Line", "Drank"))
                    .foregroundStyle(Color.grog)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Night", point.date), y: .value("Hours", y(point.units)))
                    .foregroundStyle(Color.grog)
                    .symbolSize(20)
            }
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 2)) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(Int(value.as(Double.self) ?? 0))") }
            }
            AxisMarks(position: .trailing, values: Array(stride(from: 0, through: most, by: step)).map(y)) { value in
                AxisValueLabel { Text("\(Int(((value.as(Double.self) ?? 0) / top * most).rounded()))") }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: 14 * 86_400)
        .chartScrollPosition(x: $x)
        .frame(height: 200)
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
        let current = ledger.runningTotal(entries, over: start...(start + 6), through: today)
        let weeks = (1...3).map { ledger.runningTotal(entries, over: (start - 7 * $0)...(start - 7 * $0 + 6)) }
        // A week with nothing logged has no line, and an earlier week does not stand in for it as "last week".
        let earlier = weeks.filter { $0.count > 1 }
        let budget = goal.isEnabled ? ledger.weekBudgetCurve(of: start, goal: goal) : []
        let into = Double(start.distance(to: today)) + min(1, clock.hours(.now, into: today) / 24)
        let lastWeek = weeks[0].count > 1 ? weeks[0].last { $0.x <= into }?.units : nil
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

            WeekPlot(earlier: earlier, budget: budget, current: current,
                     weekdays: (0...6).map { (start + $0).date(in: clock.calendar).formatted(.dateTime.weekday(.abbreviated)) })

            HStack(spacing: 16) {
                LegendKey(label: "This week", color: .grog)
                LegendKey(label: "Earlier weeks", color: .gray.opacity(0.4))
                if !budget.isEmpty { LegendKey(label: "Budget", color: .dry, dashed: true) }
            }
        }
    }
}

private struct WeekPlot: View, Equatable {
    let earlier: [[CurvePoint]]
    let budget: [CurvePoint]
    let current: [CurvePoint]
    let weekdays: [String]

    var body: some View {
        Chart {
            ForEach(Array(earlier.enumerated()), id: \.offset) { index, week in
                ForEach(week) { point in
                    LineMark(x: .value("Day", point.x), y: .value("Units", point.units), series: .value("Week", "-\(index + 1)"))
                        // Faint, and fainter with age, as the earlier days are on the Day chart: context, not data to read.
                        .foregroundStyle(Color.gray.opacity([0.4, 0.25, 0.15][min(index, 2)]))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            ForEach(budget) { point in
                LineMark(x: .value("Day", point.x), y: .value("Units", point.units), series: .value("Week", "budget"))
                    .foregroundStyle(Color.dry)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
            }
            ForEach(current) { point in
                AreaMark(x: .value("Day", point.x), yStart: .value("Units", 0), yEnd: .value("Units", point.units))
                    .foregroundStyle(LinearGradient(colors: [Color.grog.opacity(0.3), Color.grog.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", point.x), y: .value("Units", point.units), series: .value("Week", "this"))
                    .foregroundStyle(Color.grog)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if let last = current.last {
                PointMark(x: .value("Day", last.x), y: .value("Units", last.units))
                    .foregroundStyle(Color.grog)
                    .symbolSize(80)
            }
        }
        .chartXScale(domain: 0...7)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis {
            AxisMarks(values: Array(0...6).map(Double.init)) { value in
                AxisGridLine()
                AxisValueLabel { Text(weekdays[Int(value.as(Double.self) ?? 0)]) }
            }
        }
        .frame(height: 200)
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
        let current = ledger.runningTotal(entries, over: thisMonth...(thisMonth + thisMonth.daysInMonth - 1), through: today)
        let previous = ledger.runningTotal(entries, over: lastMonth...(thisMonth - 1))
        let dayOfMonth = today.components.day
        let lastAtSameDay = previous.last { $0.x <= Double(dayOfMonth) }?.units ?? 0
        let now = current.last?.units ?? 0
        // A month with nothing logged has no line. The comparison also needs a logged day by this point in it: days
        // never logged are a gap, and a zero would read as a dry start to the month.
        let hasLastMonth = previous.count > 1
        let comparable = hasLastMonth && (0..<min(dayOfMonth, lastMonth.daysInMonth)).contains { ledger.isLogged(lastMonth + $0) }

        Card(title: "This month") {
            HStack(alignment: .firstTextBaseline) {
                Text(now.unitsText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("units").foregroundStyle(.secondary)
                Spacer()
                if comparable, lastAtSameDay > 0 {
                    let change = (now - lastAtSameDay) / lastAtSameDay
                    Label(change.formatted(.percent.precision(.fractionLength(0))), systemImage: change <= 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.headline)
                        .foregroundStyle(change <= 0 ? Color.dry : Color.over)
                }
            }
            if comparable {
                Text("Last month by day \(dayOfMonth): \(lastAtSameDay.unitsText) u")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            MonthPlot(previous: hasLastMonth ? previous : [], current: current, dayOfMonth: dayOfMonth)

            HStack(spacing: 16) {
                LegendKey(label: thisMonth.date(in: calendar).formatted(.dateTime.month(.wide)), color: .grog)
                if hasLastMonth {
                    LegendKey(label: lastMonth.date(in: calendar).formatted(.dateTime.month(.wide)), color: .gray.opacity(0.4))
                }
            }
        }
    }
}

private struct MonthPlot: View, Equatable {
    let previous: [CurvePoint]
    let current: [CurvePoint]
    let dayOfMonth: Int

    var body: some View {
        Chart {
            ForEach(previous) {
                LineMark(x: .value("Day", $0.x), y: .value("Units", $0.units), series: .value("Month", "Last"))
                    .foregroundStyle(Color.gray.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(current) {
                AreaMark(x: .value("Day", $0.x), yStart: .value("Units", 0), yEnd: .value("Units", $0.units))
                    .foregroundStyle(LinearGradient(colors: [Color.grog.opacity(0.35), Color.grog.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", $0.x), y: .value("Units", $0.units), series: .value("Month", "This"))
                    .foregroundStyle(Color.grog)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if let last = current.last {
                PointMark(x: .value("Day", last.x), y: .value("Units", last.units))
                    .foregroundStyle(Color.grog)
                    .symbolSize(80)
            }
            RuleMark(x: .value("Today", Double(dayOfMonth)))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        }
        .chartXScale(domain: 0...31)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis {
            AxisMarks(values: [1, 8, 15, 22, 29]) { AxisGridLine(); AxisValueLabel() }
        }
        .frame(height: 200)
    }
}

/// Weekly units as bars against the tapering budget.
private struct WeeksCard: View {
    let stats: [WeekStat]
    let nights: Nights
    @Binding var weeks: Int
    @Environment(Prefs.self) private var prefs
    /// Held for the same reason as the progress charts', and dropped when the range changes so a new range opens on
    /// the latest weeks.
    @State private var scrolledTo: Date?
    @AppStorage("chartHeartReading") private var shownHeart = HeartReading.hrv

    var body: some View {
        let calendar = prefs.clock.calendar
        let starts = stats.map(\.start)
        let hearts = [HeartReading.resting, .hrv].flatMap { reading in
            HeartPoint.line(reading, starts, at: { $0.date(in: calendar) }) { nights.mean(reading.value, over: $0...($0 + 6)) }
        }
        Card(title: "Weekly") {
            Picker("Range", selection: $weeks) {
                Text("8 weeks").tag(8)
                Text("12 weeks").tag(12)
                Text("6 months").tag(26)
                Text("1 year").tag(52)
            }
            .pickerStyle(.segmented)

            WeeksPlot(stats: stats, heart: hearts.filter { $0.reading == HeartLegend.drawn(shownHeart, in: hearts) }, weeks: weeks, calendar: calendar,
                      x: Binding(get: { scrolledTo ?? (stats.last!.start - 7 * (weeks - 1)).date(in: calendar) }, set: { scrolledTo = $0 }))
                .onChange(of: weeks) { scrolledTo = nil }

            HStack(spacing: 16) {
                LegendKey(label: "Units", color: .grog)
                LegendKey(label: "Budget", color: .dry)
                Spacer()
                Text("scroll back").font(.caption).foregroundStyle(.tertiary)
            }
            HeartLegend(points: hearts, suffix: "", shown: $shownHeart)
        }
    }
}

private struct WeeksPlot: View, Equatable {
    let stats: [WeekStat]
    let heart: [HeartPoint]
    let weeks: Int
    let calendar: Calendar
    @Binding var x: Date

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stats == rhs.stats && lhs.heart == rhs.heart && lhs.weeks == rhs.weeks && lhs.calendar == rhs.calendar
    }

    var body: some View {
        let top = max(Units.weeklyGuideline, stats.map(\.totals.units).max() ?? 0, stats.compactMap(\.budget).max() ?? 0) * 1.15
        let heartScale = HeartScale(heart, top: top)
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
                RuleMark(x: .value("This week", thisWeek.addingTimeInterval(3 * 24 * 3600)))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
            RuleMark(y: .value("Guideline", Units.weeklyGuideline))
                .foregroundStyle(.secondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("14 u guideline").font(.caption2).foregroundStyle(.secondary)
                }
            // Resting rate is the heavier line, since it keeps falling for weeks after the drinking does.
            if let heartScale {
                ForEach(heart) { point in
                    LineMark(x: .value("Week", point.date, unit: .weekOfYear), y: .value("Units", heartScale.y(point.value)), series: .value("Line", point.series))
                        .foregroundStyle(point.reading.color.opacity(point.bridge ? 0.6 : 1))
                        .lineStyle(StrokeStyle(lineWidth: (point.reading == .resting ? 2.5 : 1.5) * (point.bridge ? 0.6 : 1), lineCap: .round, lineJoin: .round, dash: point.bridge ? [3, 4] : []))
                    if !point.bridge, point.alone {
                        PointMark(x: .value("Week", point.date, unit: .weekOfYear), y: .value("Units", heartScale.y(point.value)))
                            .foregroundStyle(point.reading.color)
                            .symbolSize(30)
                    }
                }
            }
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading)
            if let heartScale { heartScale.axis }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: Double(weeks) * 7 * 86_400)
        .chartScrollPosition(x: $x)
        .frame(height: 220)
    }
}

private struct SummaryTiles: View {
    let ledger: Ledger
    let stats: [WeekStat]
    let days: ClosedRange<DayKey>
    let currency: String

    var body: some View {
        let totals = stats.reduce(DayTotals()) { $0 + $1.totals }
        let dry = stats.reduce(0) { $0 + $1.dryDays }
        let unlogged = stats.reduce(0) { $0 + $1.unloggedDays }
        // Complete weeks only: this one is still being drunk.
        let average = stats.count > 1 ? ledger.weeklyAverage(over: stats[0].start...(stats[stats.count - 1].start - 1)) : nil

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

/// Which weekdays carry the most drinking: average units per weekday across logged days.
private struct WeekdayCard: View {
    let ledger: Ledger
    let days: ClosedRange<DayKey>

    var body: some View {
        let calendar = ledger.clock.calendar
        let byWeekday = Dictionary(grouping: days.filter(ledger.isLogged), by: \.weekday)
        let order = (0..<7).map { ($0 + calendar.firstWeekday - 1) % 7 + 1 }
        let symbols = calendar.shortWeekdaySymbols
        let bars = order.map { weekday -> WeekdayBar in
            let days = byWeekday[weekday] ?? []
            let average = days.isEmpty ? 0 : days.reduce(0) { $0 + ledger.totals(on: $1).units } / Double(days.count)
            return WeekdayBar(label: symbols[weekday - 1], average: average, isToday: weekday == ledger.today.weekday)
        }

        Card(title: "By weekday") {
            WeekdayPlot(bars: bars)
        }
    }
}

private struct WeekdayBar: Equatable {
    let label: String
    let average: Double
    let isToday: Bool
}

private struct WeekdayPlot: View, Equatable {
    let bars: [WeekdayBar]

    var body: some View {
        Chart {
            ForEach(bars, id: \.label) { bar in
                BarMark(x: .value("Day", bar.label), y: .value("Units", bar.average))
                    .foregroundStyle(Color.grog.opacity(bar.isToday ? 1 : 0.45).gradient)
                    .clipShape(.rect(cornerRadius: 4))
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 160)
    }
}
