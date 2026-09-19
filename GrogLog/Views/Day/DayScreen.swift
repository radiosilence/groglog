import GRDBQuery
import SwiftUI

/// A day with prev/next navigation.
struct DayPager: View {
    @State var day: DayKey

    var body: some View {
        LedgerReader { ledger in
            DayScreen(day: day, ledger: ledger)
                .id(day)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Previous day", systemImage: "chevron.left") { day = day - 1 }
                        Button("Next day", systemImage: "chevron.right") { day = day + 1 }
                            .disabled(day >= ledger.today)
                    }
                }
        }
    }
}

struct DayScreen: View {
    let day: DayKey
    let ledger: Ledger
    @Query<EntriesRequest> private var entries: [Entry]
    @Environment(Prefs.self) private var prefs
    @Environment(\.databaseContext) private var database
    @State private var adding = false
    @State private var editing: Entry?
    @State private var settingGoal = false
    @State private var settingSpend = false

    init(day: DayKey, ledger: Ledger) {
        self.day = day
        self.ledger = ledger
        _entries = Query(constant: EntriesRequest(days: day...day))
    }

    var body: some View {
        let logbook = database.logbook(prefs)
        let status = ledger.status(on: day)
        let budget = ledger.dailyBudget(on: day, goal: prefs.goal)
        let totals = ledger.totals(on: day)
        let spendOverride = ledger.spendOverride(on: day)

        List {
            Section {
                TotalsHeader(totals: totals, budget: budget, currency: prefs.currency)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
                TimelineView(.everyMinute) { timeline in
                    DayChart(day: day, ledger: ledger, budget: budget, tick: timeline.date)
                }
            }

            if let budget {
                Section("Budget") {
                    BudgetBar(used: totals.units, budget: budget)
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

            if status == .drank || spendOverride != nil {
                Section {
                    Button { settingSpend = true } label: {
                        LabeledContent("Spent", value: totals.cost.money(prefs.currency))
                            .foregroundStyle(spendOverride == nil ? .secondary : Color.grog)
                    }
                    .tint(.primary)
                } footer: {
                    Text(spendOverride == nil
                         ? "Added up from what each drink cost. Set the day's total instead if you'd rather not price every round."
                         : "Set by hand for the day. What the drinks cost is ignored until you clear it.")
                }
            }

            switch status {
            case .drank:
                Section("Drinks") {
                    ForEach(entries.reversed()) { entry in
                        Button { editing = entry } label: { PourRow(entry: entry) }
                            .tint(.primary)
                    }
                    .onDelete { offsets in
                        let reversed = Array(entries.reversed())
                        offsets.forEach { logbook.delete(reversed[$0].pour) }
                    }
                }
            case .alcoholFree:
                Section {
                    Label("Alcohol-free day", systemImage: "leaf.fill")
                        .font(.headline)
                        .foregroundStyle(Color.dry)
                    Button("Not alcohol-free after all", role: .destructive) {
                        logbook.setAlcoholFree(false, on: day)
                    }
                }
            case .today, .unlogged, .untracked:
                Section {
                    Button {
                        logbook.setAlcoholFree(true, on: day)
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
        .sensoryFeedback(.success, trigger: status) { _, new in new == .alcoholFree }
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
        .sheet(isPresented: $settingGoal) { GoalSheet(goal: prefs.goal) }
        .sheet(isPresented: $settingSpend) { SpendSheet(day: day, derived: ledger.derivedSpend(on: day), override: spendOverride) }
        .sheet(item: $editing) { entry in
            PourEditor(entry: entry, day: day)
        }
    }

    private var title: String {
        if day == ledger.today { return "Today" }
        if day == ledger.today - 1 { return "Yesterday" }
        return day.date(in: ledger.clock.calendar).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// A day's spend set in one go, for a night you know the damage but not each round. Cleared, it falls back to what
/// the drinks add up to.
private struct SpendSheet: View {
    let day: DayKey
    let derived: Double
    let override: Double?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.databaseContext) private var database
    @Environment(Prefs.self) private var prefs
    @State private var amount: Double

    init(day: DayKey, derived: Double, override: Double?) {
        self.day = day
        self.derived = derived
        self.override = override
        _amount = State(initialValue: override ?? derived)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(label: "Spent", value: $amount, currency: prefs.currency)
                } footer: {
                    Text("Stands in for what the drinks add up to. Units and calories are unaffected.")
                }
                if override != nil {
                    Section {
                        Button("Back to drink prices", role: .destructive) {
                            database.logbook(prefs).setSpend(nil, on: day)
                            dismiss()
                        }
                    } footer: {
                        Text("The drinks logged come to \(derived.money(prefs.currency)).")
                    }
                }
            }
            .navigationTitle("Spent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", role: .confirm) {
                        database.logbook(prefs).setSpend(amount, on: day)
                        dismiss()
                    }
                }
            }
        }
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
    let entry: Entry

    var body: some View {
        HStack(spacing: 12) {
            DrinkGlyph(category: entry.category, vessel: entry.vessel, volumeMl: entry.volumeMl)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.body.weight(.medium))
                Text(entry.category.serving(entry.vessel, ml: entry.volumeMl, abv: entry.abv))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.units.unitsText) u").font(.body.weight(.semibold).monospacedDigit())
                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
