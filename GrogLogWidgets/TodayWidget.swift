import Charts
import GRDB
import SwiftUI
import WidgetKit

/// Today on the Lock Screen, and a tap into the Log grid — the whole point being that logging a drink standing at
/// a bar costs two taps rather than finding the app first.
@main
struct GrogLogWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        LogWidget()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "cc.blit.groglog.today", provider: TodayProvider()) { entry in
            TodayView(entry: entry)
                .widgetURL(URL(string: "groglog://log"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("What you've had today against the day's budget. Tap to log.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayEntry: TimelineEntry {
    var date = Date.now
    var units = 0.0
    var budget: Double?
    var isDry = false
    /// Units through the day, stepping at each drink — the same running total the Day screen draws.
    var curve: [CurvePoint] = []
    /// Tiles to log from, in the Log grid's order.
    var tiles: [ServeEntity] = []

    /// The budget draining through the day. Once it's gone the line sits at zero rather than going negative,
    /// because "how far under" stops being the question.
    var burndown: [CurvePoint] {
        guard let budget else { return curve }
        return curve.map { CurvePoint(x: $0.x, units: max(0, budget - $0.units)) }
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(units: 3.5, budget: 4.5)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        Task { completion(await today()) }
    }

    /// One entry, good until the day ends — the app reloads the timeline itself whenever anything is logged.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        Task {
            let clock = Store.logbook.clock
            completion(Timeline(entries: [await today()], policy: .after(clock.end(of: clock.today))))
        }
    }

    private func today() async -> TodayEntry {
        let logbook = Store.logbook
        let goal = Store.goal
        let day = logbook.clock.today
        let read = try? await logbook.writer.read { db in
            (days: try Day.fetchAll(db),
             entries: try EntriesRequest(days: day...day).fetch(db),
             tiles: try Serve.grid(db).prefix(4).map(ServeEntity.init))
        }
        let ledger = Ledger(days: read?.days ?? [], clock: logbook.clock)
        return TodayEntry(
            units: ledger.totals(on: day).units,
            budget: ledger.dailyBudget(on: day, goal: goal),
            isDry: ledger.status(on: day) == .alcoholFree,
            // Only as far as now: the rest of the day hasn't happened, and drawing it flat says it went well.
            curve: ledger.cumulative(read?.entries ?? [], on: day, through: logbook.clock.hours(.now, into: day)),
            tiles: read?.tiles ?? []
        )
    }
}

struct TodayView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            // The ring means "against your budget", so with no goal there's nothing for it to fill and it says so
            // by not being there. Clamping to the guideline instead pinned it full all evening, which reads as broken.
            if let budget = entry.budget, budget > 0 {
                Gauge(value: min(entry.units, budget), in: 0...budget) {
                    Text("u")
                } currentValueLabel: {
                    Text(entry.units.unitsText)
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                VStack(spacing: -2) {
                    Text(entry.units.unitsText).font(.title2.bold())
                    Text("units").font(.caption2)
                }
            }
        case .accessoryInline:
            Label(inline, systemImage: entry.isDry ? "checkmark.circle" : "mug.fill")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.units.unitsText) u").font(.title2.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inline: String {
        if entry.isDry { return "Dry today" }
        guard let budget = entry.budget else { return "\(entry.units.unitsText) u today" }
        return "\(entry.units.unitsText) of \(budget.unitsText) u"
    }

    /// Over the budget reads as how far over, rather than as a negative amount left.
    private var detail: String {
        if entry.isDry { return "Alcohol-free" }
        guard let budget = entry.budget else { return "today" }
        let left = budget - entry.units
        return left >= 0 ? "\(left.unitsText) of \(budget.unitsText) left" : "\((-left).unitsText) over \(budget.unitsText)"
    }
}

/// The Home Screen widget: your usuals as buttons that log without opening anything, and what the day has left.
struct LogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "cc.blit.groglog.log", provider: TodayProvider()) { entry in
            LogView(entry: entry)
                .widgetURL(URL(string: "groglog://log"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Log")
        .description("Your usuals, one tap each, against what's left of the day's budget.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LogView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HStack(spacing: 10) {
            summary
            if family == .systemMedium, !entry.tiles.isEmpty {
                tiles.frame(width: 168)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(entry.units.unitsText) u").font(.title2.bold())
            Text(detail)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.secondary)
            Burndown(entry: entry).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Four at most: a tile you have to hunt for on a Home Screen isn't faster than opening the app.
    private var tiles: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(entry.tiles.chunked(), id: \.first?.id) { row in
                GridRow {
                    ForEach(row, id: \.id) { Tile(serve: $0) }
                }
            }
        }
    }

    private var detail: String {
        if entry.isDry { return "Alcohol-free" }
        guard let budget = entry.budget else { return "today" }
        let left = budget - entry.units
        return left >= 0 ? "\(left.unitsText) left of \(budget.unitsText)" : "\((-left).unitsText) over \(budget.unitsText)"
    }
}

private struct Tile: View {
    let serve: ServeEntity

    var body: some View {
        Button(intent: LogDrinkIntent(serve: serve)) {
            VStack(spacing: 1) {
                // Two lines and a scale floor: the catalogue is full of "Fuller's London Pride (bottle)", and a
                // name clipped mid-word tells you less than a small one.
                Text(serve.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                // The size is half of what's about to be logged — a can and a bottle of the same beer differ by a unit.
                Text("\(serve.shortSize) · \(serve.units.unitsText) u")
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary, in: .rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

/// The budget draining through the day, or — with no goal — the units climbing.
private struct Burndown: View {
    let entry: TodayEntry

    var body: some View {
        Chart(entry.burndown) { point in
            AreaMark(x: .value("Hour", point.x), y: .value("Units", point.units))
                .foregroundStyle(Color.grog.opacity(0.22))
            LineMark(x: .value("Hour", point.x), y: .value("Units", point.units))
                .foregroundStyle(Color.grog)
                .interpolationMethod(.stepEnd)
        }
        .chartXScale(domain: 0...24)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

private extension Array where Element == ServeEntity {
    func chunked() -> [[ServeEntity]] {
        stride(from: 0, to: count, by: 2).map { Array(self[$0..<Swift.min($0 + 2, count)]) }
    }
}

#Preview("Home Screen", as: .systemMedium) {
    LogWidget()
} timeline: {
    TodayEntry(
        units: 3.5,
        budget: 4.5,
        curve: [CurvePoint(x: 0, units: 0), CurvePoint(x: 18, units: 1.2), CurvePoint(x: 20, units: 3.5), CurvePoint(x: 21, units: 3.5)],
        tiles: []
    )
}

#Preview("Circular", as: .accessoryCircular) {
    TodayWidget()
} timeline: {
    TodayEntry(units: 3.5, budget: 4.5)
    TodayEntry(units: 7.2, budget: 4.5)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    TodayEntry(units: 3.5, budget: 4.5)
    TodayEntry(units: 7.2, budget: 4.5)
    TodayEntry(isDry: true)
    TodayEntry(units: 2.3)
}

#Preview("Inline", as: .accessoryInline) {
    TodayWidget()
} timeline: {
    TodayEntry(units: 3.5, budget: 4.5)
    TodayEntry(isDry: true)
}
