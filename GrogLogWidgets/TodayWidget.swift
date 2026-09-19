import GRDB
import SwiftUI
import WidgetKit

/// Today on the Lock Screen, and a tap into the Log grid — the whole point being that logging a drink standing at
/// a bar costs two taps rather than finding the app first.
@main
struct GrogLogWidgets: WidgetBundle {
    var body: some Widget { TodayWidget() }
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

    /// What the ring fills against when there's no goal: the weekly guideline spread over the week.
    var limit: Double { budget ?? Units.weeklyGuideline / 7 }
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
            let clock = await Store.logbook.clock
            completion(Timeline(entries: [await today()], policy: .after(clock.end(of: clock.today))))
        }
    }

    private func today() async -> TodayEntry {
        let logbook = await Store.logbook
        let goal = await Store.goal
        let days = (try? await logbook.writer.read { try Day.fetchAll($0) }) ?? []
        let ledger = Ledger(days: days, clock: logbook.clock)
        let day = logbook.clock.today
        return TodayEntry(
            units: ledger.totals(on: day).units,
            budget: ledger.dailyBudget(on: day, goal: goal),
            isDry: ledger.status(on: day) == .alcoholFree
        )
    }
}

struct TodayView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(entry.units, entry.limit), in: 0...entry.limit) {
                Image(systemName: "mug.fill")
            } currentValueLabel: {
                Text(entry.units.unitsText)
            }
            .gaugeStyle(.accessoryCircular)
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
