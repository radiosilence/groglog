import SwiftData
import SwiftUI

struct CalendarScreen: View {
    let ledger: Ledger
    @Environment(Prefs.self) private var prefs

    var body: some View {
        let calendar = ledger.clock.calendar
        let thisMonth = calendar.dateInterval(of: .month, for: ledger.clock.today)!.start
        let earliest = calendar.dateInterval(of: .month, for: ledger.firstDay ?? thisMonth)!.start
        let first = min(earliest, calendar.date(byAdding: .month, value: -2, to: thisMonth)!)
        let months = sequence(first: first) { calendar.date(byAdding: .month, value: 1, to: $0)! }
            .prefix { $0 <= thisMonth }

        ScrollView {
            LazyVStack(spacing: 32) {
                ForEach(Array(months), id: \.self) { month in
                    MonthGrid(month: month, ledger: ledger, goal: prefs.goal)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .defaultScrollAnchor(.bottom)
        .safeAreaInset(edge: .top, spacing: 0) {
            WeekdayHeader(calendar: calendar)
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            let streak = ledger.dryStreak()
            if streak > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Label("\(streak)-day dry streak", systemImage: "leaf.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.dry)
                }
            }
        }
        .navigationDestination(for: Date.self) { DayPager(day: $0) }
    }
}

private struct WeekdayHeader: View {
    let calendar: Calendar

    var body: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        HStack {
            ForEach(0..<7, id: \.self) { index in
                Text(symbols[(index + offset) % 7])
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct MonthGrid: View {
    let month: Date
    let ledger: Ledger
    let goal: Goal

    var body: some View {
        let clock = ledger.clock
        let calendar = clock.calendar
        let count = calendar.range(of: .day, in: .month, for: month)!.count
        let days = (0..<count).map { clock.adding($0, to: month) }
        let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let units = days.reduce(0) { $0 + ledger.totals(on: $1).units }
        let dry = days.filter { ledger.status(on: $0) == .alcoholFree }.count

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title2.bold())
                Spacer()
                Text("\(units.unitsText) u · \(dry) dry")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(spacing: 5), count: 7), spacing: 5) {
                ForEach(0..<offset, id: \.self) { _ in Color.clear }
                ForEach(days, id: \.self) { day in
                    DayCell(day: day, ledger: ledger, budget: ledger.dailyBudget(on: day, goal: goal))
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let ledger: Ledger
    let budget: Double?
    @Environment(\.modelContext) private var context

    var body: some View {
        let status = ledger.status(on: day)
        let units = ledger.totals(on: day).units
        let isToday = day == ledger.clock.today
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let fill: Color = switch status {
        case .drank: Color.heat(units: units, budget: budget)
        case .alcoholFree: .dry
        default: .clear
        }

        let cell = VStack(spacing: 0) {
            Text(day.formatted(.dateTime.day()))
                .font(.caption2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(status == .drank || status == .alcoholFree ? 0.85 : 0.6)
            Spacer(minLength: 0)
            switch status {
            case .drank:
                Text(units.unitsText)
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7)
            case .alcoholFree:
                Image(systemName: "leaf.fill").font(.callout)
            case .unlogged:
                Image(systemName: "questionmark").font(.caption).foregroundStyle(.tertiary)
            default:
                EmptyView()
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(status == .drank || status == .alcoholFree ? .white : .primary)
        .padding(5)
        .frame(height: 56)
        .background(shape.fill(fill.gradient))
        .overlay {
            if isToday {
                shape.strokeBorder(Color.grog, lineWidth: 2.5)
            } else if status == .unlogged {
                shape.strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            } else if status == .future || status == .untracked {
                shape.strokeBorder(.quaternary, lineWidth: 1)
            }
        }
        .contentShape(shape)

        if status == .future {
            cell.opacity(0.5)
        } else {
            NavigationLink(value: day) { cell }
                .buttonStyle(.plain)
                .contextMenu {
                    if status == .alcoholFree {
                        Button("Not alcohol-free", systemImage: "xmark") { context.setAlcoholFree(false, on: day) }
                    } else if status != .drank {
                        Button("Alcohol-free", systemImage: "leaf") { context.setAlcoholFree(true, on: day) }
                    }
                }
        }
    }
}
