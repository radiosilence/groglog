import Charts
import SwiftData
import SwiftUI

/// Running units through the day, against yesterday and the month's average day. Fetches just the drinks in that
/// window — about a month's worth — rather than the whole history.
struct DayChart: View {
    let day: DayKey
    let ledger: Ledger
    let budget: Double?
    let now: Date
    @Query private var pours: [Pour]

    init(day: DayKey, ledger: Ledger, budget: Double?, now: Date) {
        self.day = day
        self.ledger = ledger
        self.budget = budget
        self.now = now
        _pours = Query(Pour.on(ledger.monthBefore(day).lowerBound...day))
    }

    var body: some View {
        let clock = ledger.clock
        let yesterday = day - 1
        let nowHour = day == ledger.today ? clock.hours(now, into: day) : nil
        let firstHour = pours
            .filter { $0.day == day.number || $0.day == yesterday.number }
            .map { clock.hours($0.timestamp, into: $0.dayKey) }
            .min()
        let from = max(0, min(10, (firstHour ?? 10) - 1).rounded(.down))

        let yesterdayLogged = ledger.isLogged(yesterday)
        let series = [
            Series(name: "Today", color: .grog, points: ledger.cumulative(pours, on: day, from: from, through: nowHour ?? 24)),
            Series(name: "Yesterday", color: .gray.opacity(0.6), points: yesterdayLogged ? ledger.cumulative(pours, on: yesterday, from: from) : []),
            Series(name: "Month avg", color: .dry, points: ledger.averageCumulative(pours, over: ledger.monthBefore(day), from: from), dashed: true),
        ]
        let at = nowHour ?? 24
        let top = max(2, budget ?? 0, series.flatMap(\.points).map(\.units).max() ?? 0) * 1.1

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

            Chart {
                ForEach(series.reversed()) { s in
                    ForEach(s.points) { point in
                        LineMark(x: .value("Hour", point.hour), y: .value("Units", point.units), series: .value("Series", s.name))
                            .interpolationMethod(s.dashed ? .linear : .stepEnd)
                            .foregroundStyle(s.color)
                            .lineStyle(StrokeStyle(lineWidth: s.name == "Today" ? 3 : 2, lineCap: .round, dash: s.dashed ? [4, 4] : []))
                    }
                }
                ForEach(series[0].points) { point in
                    AreaMark(x: .value("Hour", point.hour), yStart: .value("Units", 0), yEnd: .value("Units", point.units))
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
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .chartXScale(domain: from...24)
            .chartYScale(domain: 0...top)
            .chartXAxis {
                AxisMarks(values: .stride(by: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel { Text(clock.hourLabel(value.as(Double.self) ?? 0)) }
                }
            }
            .frame(height: 200)

            HStack(spacing: 16) {
                ForEach(series.filter { !$0.points.isEmpty }) { s in
                    LegendKey(label: s.name, color: s.color, dashed: s.dashed)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct Series: Identifiable {
    let name: String
    let color: Color
    let points: [CurvePoint]
    var dashed = false
    var id: String { name }

    func value(at hour: Double) -> Double? {
        guard !points.isEmpty else { return nil }
        return points.last { $0.hour <= hour }?.units ?? 0
    }
}
