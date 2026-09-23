import Charts
import SwiftUI

/// Running units through the day, against the two days before it and the average day of the week before. Takes the window's
/// drinks from the screen, which fetches them once for both.
struct DayChart: View {
    let day: DayKey
    let ledger: Ledger
    let budget: Double?
    /// The last timeline tick; only there to move the "now" marker along. Drawing uses the real time, so a drink
    /// logged between ticks shows at once.
    let tick: Date
    let pours: [Entry]

    var body: some View {
        let clock = ledger.clock
        let yesterday = day - 1
        let dayBefore = day - 2
        let now = Date.now
        let nowHour = day == ledger.today ? clock.hours(now, into: day) : nil
        var hours = HourCounter(clock)
        let firstHour = pours
            .filter { $0.day == day.number || $0.day == yesterday.number || $0.day == dayBefore.number }
            .map { hours.hours($0.timestamp, into: $0.dayKey) }
            .min()
        let from = max(0, min(10, (firstHour ?? 10) - 1).rounded(.down))

        let yesterdayLogged = ledger.isLogged(yesterday)
        let series = [
            Series(name: "Today", color: .grog, points: ledger.cumulative(pours, on: day, from: from, through: nowHour ?? 24)),
            Series(name: "Yesterday", color: .gray.opacity(0.6), points: yesterdayLogged ? ledger.cumulative(pours, on: yesterday, from: from) : []),
            // Named by its weekday: "two days ago" reads as a count, not a day you remember.
            Series(name: dayBefore.date(in: clock.calendar).formatted(.dateTime.weekday(.abbreviated)), color: .gray.opacity(0.25),
                   points: ledger.isLogged(dayBefore) ? ledger.cumulative(pours, on: dayBefore, from: from) : []),
            Series(name: "Week avg", color: .dry, points: ledger.averageCumulative(pours, over: ledger.weekBefore(day), from: from), dashed: true),
        ]
        let at = nowHour ?? 24

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text(nowHour == nil ? "End of day" : "By \(now.formatted(.dateTime.hour().minute()))")
                    .foregroundStyle(.secondary)
                ForEach(series) { s in
                    if let value = s.value(at: at) {
                        Text("\(value.unitsText)")
                            .foregroundStyle(s.color)
                            .fontWeight(s.name == "Today" ? .bold : .regular)
                    }
                }
            }
            .font(.subheadline.monospacedDigit())

            DayPlot(
                series: series,
                budget: budget,
                nowHour: nowHour,
                from: from,
                hours: stride(from: from, through: 24, by: 3).map { (x: $0, label: clock.hourLabel($0)) }
            )

            HStack(spacing: 16) {
                ForEach(series.filter { !$0.points.isEmpty }) { s in
                    LegendKey(label: s.name, color: s.color, dashed: s.dashed)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// The chart alone, on plain values, so it's only laid out again when one of them changes. A chart's content
/// is a closure, which can't be compared; anything holding one is rebuilt whenever its parent is, and the
/// parent here is rebuilt on every commit.
private struct DayPlot: View, Equatable {
    let series: [Series]
    let budget: Double?
    let nowHour: Double?
    let from: Double
    let hours: [(x: Double, label: String)]

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.series == rhs.series && lhs.budget == rhs.budget && lhs.nowHour == rhs.nowHour && lhs.from == rhs.from
            && lhs.hours.map(\.x) == rhs.hours.map(\.x) && lhs.hours.map(\.label) == rhs.hours.map(\.label)
    }

    var body: some View {
        let top = max(2, budget ?? 0, series.flatMap(\.points).map(\.units).max() ?? 0) * 1.1
        Chart {
            ForEach(series.reversed()) { s in
                ForEach(s.points) { point in
                    LineMark(x: .value("Hour", point.x), y: .value("Units", point.units), series: .value("Series", s.name))
                        .interpolationMethod(s.dashed ? .linear : .stepEnd)
                        .foregroundStyle(s.color)
                        .lineStyle(StrokeStyle(lineWidth: s.name == "Today" ? 3 : 2, lineCap: .round, dash: s.dashed ? [4, 4] : []))
                }
            }
            ForEach(series[0].points) { point in
                AreaMark(x: .value("Hour", point.x), yStart: .value("Units", 0), yEnd: .value("Units", point.units))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(LinearGradient(colors: [Color.grog.opacity(0.35), Color.grog.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            }
            if let budget {
                RuleMark(y: .value("Budget", budget))
                    .foregroundStyle(Color.over.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("budget").font(.caption2).foregroundStyle(Color.over)
                    }
            }
            if let nowHour {
                RuleMark(x: .value("Now", nowHour))
                    .foregroundStyle(Color.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .chartXScale(domain: from...24)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartYScale(domain: 0...top)
        .chartXAxis {
            AxisMarks(values: hours.map(\.x)) { value in
                AxisGridLine()
                AxisValueLabel { Text(hours.first { $0.x == value.as(Double.self) }?.label ?? "") }
            }
        }
        .frame(height: 200)
    }
}

private struct Series: Identifiable, Equatable {
    let name: String
    let color: Color
    let points: [CurvePoint]
    var dashed = false
    var id: String { name }

    func value(at hour: Double) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.last { $0.x <= hour }?.units ?? 0
    }
}
