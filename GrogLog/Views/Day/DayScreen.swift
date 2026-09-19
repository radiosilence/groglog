import SwiftData
import SwiftUI

/// A day with prev/next navigation.
struct DayPager: View {
    @State var day: Date

    var body: some View {
        LedgerReader { ledger in
            DayScreen(day: day, ledger: ledger)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Previous day", systemImage: "chevron.left") { day = ledger.clock.adding(-1, to: day) }
                        Button("Next day", systemImage: "chevron.right") { day = ledger.clock.adding(1, to: day) }
                            .disabled(day >= ledger.clock.today)
                    }
                }
        }
    }
}

struct DayScreen: View {
    let day: Date
    let ledger: Ledger
    @Environment(Prefs.self) private var prefs
    @Environment(\.modelContext) private var context
    @State private var adding = false
    @State private var editing: Pour?
    @State private var settingGoal = false

    var body: some View {
        let pours = ledger.pours(on: day)
        let status = ledger.status(on: day)
        let budget = ledger.dailyBudget(on: day, goal: prefs.goal)

        List {
            Section {
                TotalsHeader(totals: DayTotals(pours), budget: budget, currency: prefs.currency)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
                TimelineView(.everyMinute) { timeline in
                    DayChart(day: day, ledger: ledger, budget: budget, now: timeline.date)
                }
            }

            if let budget {
                Section("Budget") {
                    BudgetBar(used: DayTotals(pours).units, budget: budget)
                }
            } else if prefs.goal.isEnabled {
                Section("Budget") {
                    Text("No budget yet — it's worked out from the days logged before this one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Button("Set a goal to get a daily budget", systemImage: "target") { settingGoal = true }
                }
            }

            switch status {
            case .drank:
                Section("Drinks") {
                    ForEach(pours.reversed()) { pour in
                        Button { editing = pour } label: { PourRow(pour: pour) }
                            .tint(.primary)
                    }
                    .onDelete { offsets in
                        let reversed = Array(pours.reversed())
                        offsets.forEach { context.delete(reversed[$0]) }
                    }
                }
            case .alcoholFree:
                Section {
                    Label("Alcohol-free day", systemImage: "leaf.fill")
                        .font(.headline)
                        .foregroundStyle(Color.dry)
                    Button("Not alcohol-free after all", role: .destructive) {
                        context.setAlcoholFree(false, on: day)
                    }
                }
            case .today, .unlogged, .untracked:
                Section {
                    Button {
                        context.setAlcoholFree(true, on: day)
                    } label: {
                        Label(status == .today ? "Mark today alcohol-free" : "It was alcohol-free", systemImage: "leaf")
                            .font(.headline)
                    }
                    .tint(.dry)
                } footer: {
                    Text(status == .unlogged
                         ? "Nothing logged. Mark it dry or add what you had — unmarked days stay \"not logged\" rather than counting as dry."
                         : "Days only count as dry when you say so.")
                }
            case .future:
                EmptyView()
            }
        }
        .navigationTitle(title)
        .sensoryFeedback(.success, trigger: status == .alcoholFree)
        .safeAreaInset(edge: .bottom) {
            if status != .future {
                Button { adding = true } label: {
                    Label("Add drinks", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $adding) {
            AddDrinkSheet(day: day)
        }
        .sheet(isPresented: $settingGoal) { GoalSheet() }
        .sheet(item: $editing) { pour in
            PourEditor(pour: pour, day: day, clock: ledger.clock)
        }
    }

    private var title: String {
        let today = ledger.clock.today
        if day == today { return "Today" }
        if day == ledger.clock.adding(-1, to: today) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

struct TotalsHeader: View {
    let totals: DayTotals
    let budget: Double?
    let currency: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(totals.units.unitsText)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(totals.units > 0 ? Color.heat(units: totals.units, budget: budget) : .secondary)
                    .contentTransition(.numericText(value: totals.units))
                Text(budget.map { "units of \($0.unitsText) budget" } ?? "units")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(totals.kcal.kcalText) kcal")
                Text(totals.cost.money(currency))
            }
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
        }
        .animation(.snappy, value: totals.units)
    }
}

/// What's left of the day's budget, draining as you drink rather than filling up.
struct BudgetBar: View {
    let used: Double
    let budget: Double

    var body: some View {
        let left = budget - used
        let fraction = max(0, min(1, left / budget))
        let color: Color = left < 0 ? .over : fraction < 0.25 ? .grog : .dry

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(left < 0 ? "\((-left).unitsText) u over" : "\(left.unitsText) u left")
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                Text("of \(budget.unitsText) u")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.monospacedDigit())
            .contentTransition(.numericText())

            Capsule()
                .fill(.quaternary)
                .frame(height: 10)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(color.gradient)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
        }
        .animation(.snappy, value: used)
        .padding(.vertical, 4)
    }
}

struct PourRow: View {
    let pour: Pour

    var body: some View {
        HStack(spacing: 12) {
            DrinkGlyph(category: pour.category, vessel: pour.vessel, volumeMl: pour.volumeMl)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(pour.name).font(.body.weight(.medium))
                Text(pour.category.serving(ml: pour.volumeMl, abv: pour.abv))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(pour.units.unitsText) u").font(.body.weight(.semibold).monospacedDigit())
                Text(pour.timestamp, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
