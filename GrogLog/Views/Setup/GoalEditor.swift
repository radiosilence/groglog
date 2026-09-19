import Charts
import SwiftUI

/// Pick a cut and a timeframe; the budget tapers daily from your recent average to the target.
struct GoalEditor: View {
    let ledger: Ledger
    @Environment(Prefs.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        let goal = prefs.goal
        let recent = ledger.recentWeeklyAverage()

        Section {
            Toggle("Cut down", isOn: $prefs.goal.isEnabled)
            if goal.isEnabled {
                Picker("Cut", selection: $prefs.goal.reductionPercent) {
                    ForEach([10.0, 25, 33, 50], id: \.self) { Text("−\(Int($0))%") }
                }
                .pickerStyle(.segmented)
                Picker("Every", selection: $prefs.goal.periodDays) {
                    ForEach([(1, "day"), (7, "week"), (28, "4 wk"), (56, "8 wk"), (84, "12 wk")], id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                Toggle("From today", isOn: $prefs.goal.fromToday)
                if !goal.fromToday {
                    NumberRow(label: "From", value: $prefs.goal.baselineWeekly, suffix: "u/week")
                    if let recent, abs(recent - goal.baselineWeekly) > 0.5 {
                        Button("Use my last 4 weeks (\(recent.unitsText) u/week)") {
                            prefs.goal.baselineWeekly = recent.rounded()
                        }
                    }
                    DatePicker("Starting", selection: $prefs.goal.start, displayedComponents: .date)
                }
                NumberRow(label: "Down to", value: $prefs.goal.targetWeekly, suffix: "u/week")
                BurndownPreview(goal: goal, ledger: ledger)
                if goal.isFasterThanSafe {
                    Label("That's more than 10% a day. Cutting heavy drinking that fast risks withdrawal — a slower taper is safer.", systemImage: "exclamationmark.triangle.fill")
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
                if goal.fromToday {
                    Text("Each day's budget is about \(perDay)% under what you've actually been drinking lately, down to \(goal.targetWeekly.unitsText) u/week. Go over and it simply carries on from there — no schedule to catch up with. The UK low-risk guideline is \(Int(Units.weeklyGuideline)) u/week.")
                } else {
                    let end = goal.end().map { " by \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
                    Text("\(goal.baselineWeekly.unitsText) → \(goal.targetWeekly.unitsText) u/week\(end), about \(perDay)% less each day. The UK low-risk guideline is \(Int(Units.weeklyGuideline)) u/week.")
                }
            } else {
                Text("Pick how fast to cut down and get a daily and weekly unit budget.")
            }
        }
    }
}

/// The goal as a shareable sheet, for reaching it from wherever you notice you want one.
struct GoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Prefs.self) private var prefs

    var body: some View {
        NavigationStack {
            LedgerReader { ledger in
                Form { GoalEditor(ledger: ledger) }
            }
            .navigationTitle("Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
        .onAppear { prefs.goal.isEnabled = true }
    }
}

/// The budget ahead: from the start date on a schedule, or projected forward from today.
private struct BurndownPreview: View {
    let goal: Goal
    let ledger: Ledger

    var body: some View {
        let clock = ledger.clock
        let start = goal.fromToday ? clock.today : clock.calendar.startOfDay(for: goal.start)
        let points = stride(from: 0, through: 84, by: 3).map { clock.adding($0, to: start) }
        Chart {
            ForEach(points, id: \.self) { day in
                let weekly = (ledger.dailyBudget(on: day, goal: goal) ?? 0) * 7
                AreaMark(x: .value("Date", day), y: .value("Budget", weekly))
                    .foregroundStyle(LinearGradient(colors: [Color.dry.opacity(0.4), Color.dry.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", day), y: .value("Budget", weekly))
                    .foregroundStyle(Color.dry)
            }
        }
        .chartYAxisLabel("u/week")
        .frame(height: 120)
        .padding(.vertical, 6)
    }
}
