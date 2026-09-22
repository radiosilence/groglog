import Charts
import SwiftUI

/// Pick a cut and a timeframe; the budget tapers daily from your recent average to the target.
struct GoalEditor: View {
    let ledger: Ledger
    @Binding var goal: Goal

    var body: some View {
        let recent = ledger.recentWeeklyAverage()
        // Amounts are stored per week but people think in a day's drinking, whatever the taper's pace.
        let per = "u/day"
        let amount = { (weekly: Double) in "\((weekly / 7).unitsText) u/day" }
        let perPeriod = { (keyPath: WritableKeyPath<Goal, Double>) in
            Binding(get: { goal[keyPath: keyPath] / 7 }, set: { goal[keyPath: keyPath] = $0 * 7 })
        }

        Section {
            Toggle("Cut down", isOn: $goal.isEnabled)
            if goal.isEnabled {
                Picker("Taper", selection: $goal.taper) {
                    ForEach(Taper.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if goal.taper == .linear {
                    Picker("Cut by", selection: $goal.reductionUnits) {
                        ForEach(Goal.unitCuts, id: \.self) { Text("−\($0.formatted(.number.precision(.fractionLength(0...1)))) u") }
                    }
                    .pickerStyle(.segmented)
                }
                // The share is fixed at the fastest that's safe, so how often it lands is the whole pace.
                Picker(goal.taper == .linear ? "Every" : "Cut \(Int(Goal.standardCut))% every", selection: $goal.periodDays) {
                    ForEach(Goal.periods, id: \.days) { Text($0.label).tag($0.days) }
                }
                .pickerStyle(.segmented)
                if goal.taper != .dynamic {
                    NumberRow(label: "From", value: perPeriod(\.baselineWeekly), suffix: per)
                    if let recent, abs(recent - goal.baselineWeekly) > 0.5 {
                        Button("Use my last 4 weeks (\(amount(recent)))") {
                            goal.baselineWeekly = recent
                        }
                    }
                    DatePicker("Starting", selection: $goal.start, displayedComponents: .date)
                }
                NumberRow(label: "Down to", value: perPeriod(\.targetWeekly), suffix: per)
                BurndownPreview(goal: goal, ledger: ledger)
                ProjectionRow(ledger: ledger, goal: goal)
                if goal.isFasterThanSafe {
                    Label("That's more than 10% a day. Cutting heavy drinking that fast risks withdrawal — a slower taper is safer.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.over)
                }
                // A linear taper's share grows as the budget shrinks, so the warning isn't yes or no — it's
                // a level, and only one worth naming while it's still above the guideline. It's the size of
                // the cut being warned about, never the amount left, which is the guideline's business.
                if goal.sharpensWhileItMatters {
                    Label("The same amount comes off whatever's left, so the cut deepens as a share: below \(goal.sharpensBelow.unitsText) u/day it's taking more than 10% of what remains each day. Proportional eases off instead.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.over)
                }
                if (recent ?? goal.baselineWeekly) >= Goal.withdrawalRiskWeekly {
                    Label("Around 15+ units a day, stopping suddenly can be dangerous. Taper, and consider asking your GP or a local alcohol service about support.", systemImage: "cross.case")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Goal")
        } footer: {
            if goal.isEnabled {
                let perDay = (goal.dailyCut * 100).formatted(.number.precision(.fractionLength(0...1)))
                let guideline = "The UK low-risk guideline is \(amount(Units.weeklyGuideline))."
                switch goal.taper {
                case .dynamic:
                    let window = goal.periodDays == 1 ? "yesterday" : "your average over the last \(goal.periodDays) days"
                    Text("Each day's budget is \(Int(goal.reductionPercent))% under \(window), down to \(amount(goal.targetWeekly)). Go over and it simply carries on from there — no schedule to catch up with. \(guideline)")
                case .proportional:
                    Text("\(amount(goal.baselineWeekly)) → \(amount(goal.targetWeekly)) from \(goal.start.formatted(date: .abbreviated, time: .omitted)), about \(perDay)% less each day. Takes a smaller cut as it goes, so it nears the target without quite landing on it. \(guideline)")
                case .linear:
                    Text("\(amount(goal.baselineWeekly)) → \(amount(goal.targetWeekly)) from \(goal.start.formatted(date: .abbreviated, time: .omitted)), \(goal.dailyUnitCut.unitsText) u/day less every day. The same amount off each time, so it lands on the target on a day you can name. \(guideline)")
                }
            } else {
                Text("Pick how fast to cut down and get a daily and weekly unit budget.")
            }
        }
    }
}

/// Where the taper lands if you keep to it.
struct ProjectionRow: View {
    let ledger: Ledger
    let goal: Goal

    var body: some View {
        let projection = ledger.projection(goal: goal)
        let format = { (day: DayKey) in day.date(in: ledger.clock.calendar).formatted(date: .abbreviated, time: .omitted) }
        VStack(alignment: .leading, spacing: 6) {
            if let target = projection.target {
                LabeledContent("\((goal.targetWeekly / 7).unitsText) u/day by", value: format(target))
            }
            if let stop = projection.underOneUnit {
                LabeledContent("Under 1 u/day by", value: format(stop))
                    .foregroundStyle(Color.dry)
            }
        }
        .font(.subheadline.monospacedDigit())
    }
}

/// The goal as a sheet, for reaching it from wherever you notice you want one. Edits a draft saved on Done, which
/// opens switched on — asking for the sheet is asking for a goal.
struct GoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Prefs.self) private var prefs
    @State private var draft: Goal

    init(goal: Goal) {
        var draft = goal
        draft.isEnabled = true
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            LedgerReader { ledger in
                Form { GoalEditor(ledger: ledger, goal: $draft) }
            }
            .navigationTitle("Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) {
                        prefs.goal = draft
                        dismiss()
                    }
                }
            }
        }
    }
}

/// The budget ahead: from the start date on a schedule, or projected forward from today.
private struct BurndownPreview: View {
    let goal: Goal
    let ledger: Ledger

    var body: some View {
        let calendar = ledger.clock.calendar
        let start = goal.taper == .dynamic ? ledger.today : DayKey(goal.start, in: calendar)
        let points = stride(from: 0, through: 84, by: 3).map { start + $0 }
        Chart {
            ForEach(points, id: \.self) { day in
                let amount = ledger.dailyBudget(on: day, goal: goal) ?? 0
                AreaMark(x: .value("Date", day.date(in: calendar)), y: .value("Budget", amount))
                    .foregroundStyle(LinearGradient(colors: [Color.dry.opacity(0.4), Color.dry.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", day.date(in: calendar)), y: .value("Budget", amount))
                    .foregroundStyle(Color.dry)
            }
        }
        .chartYAxisLabel("u/day")
        .frame(height: 120)
        .padding(.vertical, 6)
    }
}
