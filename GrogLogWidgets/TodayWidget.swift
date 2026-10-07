import Charts
import GRDB
import SwiftUI
import WidgetKit

/// Today on the Lock Screen, with a tap into the Log grid, so logging a drink at a bar takes two taps instead of
/// finding the app first.
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
        .description("What you have drunk today against the day's budget. Tap to log.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayEntry: TimelineEntry {
    var date = Date.now
    var units = 0.0
    var budget: Double?
    var isDry = false
    /// Units through the day, stepping at each drink: the same running total the Day screen draws.
    var curve: [CurvePoint] = []
    /// Tiles to log from, in the Log grid's order.
    var tiles: [ServeEntity] = []

    /// The line under the total on both widgets: what remains of the budget, or that the day was dry.
    var detail: String {
        if isDry { return "Alcohol-free" }
        return budget.map { units.leftText(of: $0) } ?? "today"
    }

    /// How the day is going, in the app's colours: teal inside the budget, amber just over, red well past it.
    var heat: Color { Color.heat(units: units, budget: budget) }

    /// The share of the budget still left, 0 once it is spent, as the Day screen's budget bar drains.
    var left: Double? {
        guard let budget, budget > 0 else { return nil }
        return max(0, min(1, (budget - units) / budget))
    }

    /// The budget draining through the day. Once spent, the line stays at zero rather than going negative, since
    /// the detail line already reports how far over.
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

    /// One entry, valid until the day ends; the app reloads the timeline whenever anything is logged.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        Task {
            let clock = Prefs().clock
            completion(Timeline(entries: [await today()], policy: .after(clock.end(of: clock.today))))
        }
    }

    private func today() async -> TodayEntry {
        guard let logbook = try? Store.logbook() else { return TodayEntry() }
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
            // Only as far as now: drawing the rest of the day flat would imply nothing more was drunk.
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
            DrainRing(entry: entry)
        case .accessoryInline:
            Label(inline, systemImage: entry.isDry ? "checkmark.circle" : "mug.fill")
        default:
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(entry.units.unitsText).font(.system(.title, design: .rounded, weight: .bold))
                    Text("units").font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                if let left = entry.left {
                    DrainBar(left: left, color: entry.heat).frame(height: 5)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inline: String {
        if entry.isDry { return "Dry today" }
        guard let budget = entry.budget else { return "\(entry.units.unitsText) u today" }
        return "\(entry.units.unitsText) of \(budget.unitsText) u"
    }
}

/// The Home Screen widget: the Log grid's first tiles as buttons that log without opening the app, and what the day has left.
struct LogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "cc.blit.groglog.log", provider: TodayProvider()) { entry in
            LogView(entry: entry)
                .widgetURL(URL(string: "groglog://log"))
                // The Log screen's colours: grouped background, tiles as cards on it.
                .containerBackground(Color(.systemGroupedBackground), for: .widget)
        }
        .configurationDisplayName("Log")
        .description("Your usual drinks, one tap each, against what is left of the day's budget.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LogView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HStack(spacing: 12) {
            summary
            if family == .systemMedium, !entry.tiles.isEmpty {
                tiles.frame(width: 184)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The Day screen's total: large, rounded, and coloured by how the day is going.
            Text(entry.units.unitsText)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(entry.units > 0 ? entry.heat : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(entry.budget == nil ? "units today" : "units")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Burndown(entry: entry).padding(.top, 6)
            Text(entry.detail)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(entry.isDry ? Color.dry : entry.units > 0 ? entry.heat : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Four at most: a tile that has to be hunted for on a Home Screen is no faster than opening the app.
    private var tiles: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(entry.tiles.chunked(), id: \.first?.id) { row in
                GridRow {
                    ForEach(row, id: \.id) { Tile(serve: $0) }
                }
            }
        }
    }
}

private struct Tile: View {
    let serve: ServeEntity

    var body: some View {
        Button(intent: LogDrinkIntent(serve: serve)) {
            VStack(spacing: 1) {
                DrinkGlyph(category: serve.category, vessel: serve.vessel, volumeMl: serve.volumeMl)
                    .frame(maxHeight: .infinity)
                // As on the Log grid, the name shrinks first and then truncates in the middle, where a long catalogue
                // name such as "Fuller's London Pride (bottle)" loses the least.
                Text(serve.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.middle)
                // The size matters as much as the name: a can and a bottle of the same beer differ by a unit.
                HStack(spacing: 3) {
                    Text(serve.shortSize).foregroundStyle(.secondary)
                    Text("\(serve.units.unitsText) u").fontWeight(.bold).foregroundStyle(Color.grog)
                }
                .font(.system(size: 10).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// The budget draining through the day or, with no goal, the units climbing.
private struct Burndown: View {
    let entry: TodayEntry

    var body: some View {
        let color = entry.heat
        Chart(entry.burndown) { point in
            AreaMark(x: .value("Hour", point.x), y: .value("Units", point.units))
                .foregroundStyle(color.opacity(0.22))
                .interpolationMethod(.stepEnd)
            LineMark(x: .value("Hour", point.x), y: .value("Units", point.units))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.stepEnd)
        }
        .chartXScale(domain: 0...24)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

/// The day's budget as a ring that drains as drinks are logged, like the Day screen's budget bar, with the total
/// inside. Lock Screen accessories render in one tint, so the ring's length carries the reading and the colour only
/// repeats it where the system shows colour.
private struct DrainRing: View {
    let entry: TodayEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            // The ring measures against the budget, so with no goal it is left out. Clamping to the guideline instead
            // would pin it full all evening, which looks broken.
            if let left = entry.left {
                Circle().stroke(.tertiary, lineWidth: 4).padding(3)
                Circle()
                    .trim(from: 0, to: left)
                    .stroke(entry.heat, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                    .widgetAccentable()
            }
            VStack(spacing: -3) {
                Text(entry.units.unitsText)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(entry.units > (entry.budget ?? .infinity) ? "over" : "units")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 8)
        }
    }
}

/// The Day screen's budget bar at Lock Screen size.
private struct DrainBar: View {
    let left: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(.tertiary)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * left)
                        .widgetAccentable()
                }
            }
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
        tiles: [
            Serve(Drink(name: "Staropramen", category: .beer, abv: 5, vessel: .pint, volumeMl: 568)),
            Serve(Drink(name: "Fuller's London Pride (bottle)", category: .beer, abv: 4.7, vessel: .bottle, volumeMl: 500)),
            Serve(Drink(name: "Red wine", category: .redWine, abv: 12, vessel: .wineGlass, volumeMl: 175)),
            Serve(Drink(name: "Whisky", category: .spirit, abv: 40, vessel: .tumbler, volumeMl: 50)),
        ].map(ServeEntity.init)
    )
    TodayEntry(units: 7.2, budget: 4.5, curve: [CurvePoint(x: 0, units: 0), CurvePoint(x: 19, units: 7.2), CurvePoint(x: 22, units: 7.2)])
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
