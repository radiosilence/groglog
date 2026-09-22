import Charts
import SwiftUI

/// Pick a cut and a timeframe; the budget tapers daily from your recent average to the target.
struct GoalEditor: View {
    let ledger: Ledger
    @Binding var goal: Goal

    /// Put the plan back on a pace that's on offer, after something moved that changes which are.
    /// Steps to the quickest still allowed rather than the gentlest, so raising the starting figure
    /// costs as little pace as it has to.
    private func settle() {
        // Dynamic picks its own pace off the ladder, so there's nothing of its to put back.
        guard goal.taper != .dynamic else { return }
        let from = goal.baselineWeekly
        goal.periodDays = Goal.nearestOffered(period: goal.periodDays, from: from)
        goal.reductionUnits = Goal.nearestOffered(units: goal.reductionUnits, from: from, perDays: goal.periodDays)
    }

    var body: some View {
        let recent = ledger.recentWeeklyAverage()
        // Two different questions. What they're actually drinking is what the NICE thresholds are
        // about. What the taper counts down from is what decides the size of its steps, and that's
        // the baseline for a scheduled plan — which is why editing it changes what's on offer.
        let drinking = recent ?? goal.baselineWeekly
        // All three count down from the baseline now, so that's what sets the size of their steps.
        let from = goal.baselineWeekly
        // Amounts are stored per week but people think in a day's drinking, whatever the taper's pace.
        let per = "u/day"
        let amount = { (weekly: Double) in "\((weekly / 7).unitsText) u/day" }
        let perPeriod = { (keyPath: WritableKeyPath<Goal, Double>) in
            Binding(get: { goal[keyPath: keyPath] / 7 }, set: { goal[keyPath: keyPath] = $0 * 7 })
        }

        Section {
            Toggle("Cut down", isOn: $goal.isEnabled)
            if goal.isEnabled {
                LabeledContent("Taper") { EmptyView() }
                ChipRow(options: Taper.allCases, selection: $goal.taper, label: \.label)
                Text(goal.taper.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                let offeredPeriods = Goal.periods(from: from).map(\.days)
                let offeredUnits = Goal.unitCuts(from: from, perDays: goal.periodDays)
                // Dynamic has no pace to pick: it takes the one its ladder gives for where you are.
                if goal.taper == .dynamic {
                    LabeledContent("Starts at") {
                        Text("10% every \(Goal.periods.first { $0.days == Goal.pace(drinking: from) }?.label ?? "week")")
                            .foregroundStyle(Color.grog)
                    }
                } else if goal.taper == .linear {
                    LabeledContent("Cut by") { EmptyView() }
                    ChipRow(options: Goal.unitCuts, selection: $goal.reductionUnits,
                            isEnabled: offeredUnits.contains) { "−\($0.formatted(.number.precision(.fractionLength(0...1)))) u" }
                }
                // The share is fixed at the fastest that's safe, so how often it lands is the whole pace.
                if goal.taper != .dynamic {
                    LabeledContent(goal.taper == .linear ? "Every" : "Cut \(Int(Goal.standardCut))% every") { EmptyView() }
                    ChipRow(options: Goal.periods.map(\.days), selection: $goal.periodDays,
                            isEnabled: offeredPeriods.contains) { days in
                        Goal.periods.first { $0.days == days }?.label ?? "\(days) days"
                    }
                }
                Group {
                    NumberRow(label: "From", value: perPeriod(\.baselineWeekly), suffix: per, onEditingEnded: settle)
                    // To the nearest unit a day. The average is 30.486 a day and nobody plans from that.
                    if let recent {
                        let rounded = (recent / 7).rounded() * 7
                        if abs(rounded - goal.baselineWeekly) > 0.5 {
                            Button("Use my last 4 weeks (\(amount(rounded)))") { goal.baselineWeekly = rounded }
                        }
                    }
                    DatePicker("Starting", selection: $goal.start, displayedComponents: .date)
                }
                // Greying happens as you type, because seeing it narrow is the point. Moving the
                // selection doesn't: that waits for the field to be let go of, or for a change that
                // isn't typing at all. See `settle`.
                .onChange(of: goal.taper, initial: true) { settle() }
                .onChange(of: goal.periodDays) { settle() }
                NumberRow(label: "Down to", value: perPeriod(\.targetWeekly), suffix: per)
                BurndownPreview(goal: goal, ledger: ledger)
                ProjectionRow(ledger: ledger, goal: goal)
                if goal.isFasterThanSafe {
                    Label("That's more than 10% a day, which UK treatment guidance gives as the ceiling for cutting down without medication. A slower taper is safer.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.over)
                }
                // The same guidance names 25 units a day as a reason to halve the pace, and NICE gives
                // two thresholds above it where the answer isn't a slower plan but somebody qualified.
                if drinking >= Goal.inpatientWeekly {
                    Label("Over 30 units a day. NICE points to inpatient or residential withdrawal at this level, not to cutting down alone — please talk to your GP or an alcohol service before you start.", systemImage: "cross.case.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.over)
                } else if drinking >= Goal.assistedWithdrawalWeekly {
                    Label("Over 15 units a day. NICE says to consider medically assisted withdrawal at this level — worth speaking to your GP or an alcohol service about support alongside this.", systemImage: "cross.case")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if drinking > Goal.slowerAboveWeekly {
                    Label("Over 25 units a day, guidance suggests cutting no faster than 10% every four days — so the quicker two aren't offered here.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // The pace in units, which is the thing the percentage hides: a tenth of sixty is six.
                // And when that's why an option has gone, say so rather than leaving a gap.
                let opening = goal.openingDrop(from: from)
                if opening > 0 {
                    Label("That's \(opening.unitsText) u/day off to start with.", systemImage: "arrow.down.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // A linear taper's share grows as the budget shrinks, so the warning isn't yes or no — it's
                // a level, and only one worth naming while it's still above the guideline. It's the size of
                // the cut being warned about, never the amount left, which is the guideline's business.
                if goal.sharpensWhileItMatters(from: from) {
                    Label("The same amount comes off whatever's left, so the cut deepens as a share: below \(goal.sharpensBelow.unitsText) u/day it's taking more than 10% of what remains each day. Proportional eases off instead.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.over)
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
                    Text("\(amount(goal.baselineWeekly)) → \(amount(goal.targetWeekly)) from \(goal.start.formatted(date: .abbreviated, time: .omitted)), quickening as it falls: 10% a week above 30 u/day, every four days under that, every three under 25, and every day under 15. You don't set the pace — it's the fastest the guidance allows for wherever the budget has got to. \(guideline)")
                case .proportional:
                    Text("\(amount(goal.baselineWeekly)) → \(amount(goal.targetWeekly)) from \(goal.start.formatted(date: .abbreviated, time: .omitted)), about \(perDay)% less each day. Takes a smaller cut as it goes, so it nears the target without quite landing on it. \(guideline)")
                case .linear:
                    Text("\(amount(goal.baselineWeekly)) → \(amount(goal.targetWeekly)) from \(goal.start.formatted(date: .abbreviated, time: .omitted)), \(goal.dailyUnitCut.unitsText) u/day less every day. The same amount off each time, so it lands on the target on a day you can name. \(guideline)")
                }
            } else {
                Text("Pick how fast to cut down and get a daily and weekly unit budget.")
            }
        }

        // Guidance treats a gradual reduction as something decided on for a particular person, by
        // someone who has met them. This screen can only count what you've decided; it can't tell you
        // whether a taper is the right approach, and shouldn't be read as saying that it is.
        Section {
            Text("A taper is for when cutting down gradually is already the right approach for you. Whether it is, and how fast, is a question for your GP or an alcohol service — GrogLog only keeps count of the plan you set.")
        } header: {
            Text("Before you start")
        }

        // DHSC's UK clinical guidelines for alcohol treatment, chapter 8, step 3. These are the signs
        // the guidance says to stop and get help for, not to taper more slowly through.
        Section {
            Label("A fit or seizure", systemImage: "bolt.fill")
            Label("Seeing or hearing things that aren't there", systemImage: "eye.trianglebadge.exclamationmark.fill")
            Label("Confusion, or being unsteady on your feet", systemImage: "figure.fall")
        } header: {
            Text("Call 999 if you get any of these")
        } footer: {
            Text("Withdrawal can turn serious, and these are the signs that it has. They're an emergency, not a reason to cut down more slowly.")
        }
        .foregroundStyle(Color.over)
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
        // Every day, not every third: the pace changes where the budget crosses a threshold, and
        // sampling past the corner rounds it off into something that looks like a mistake. A day with
        // no budget is left out rather than drawn as nought, which read as the plan hitting the floor.
        let start = DayKey(goal.start, in: calendar)
        let points = (0...84).compactMap { step -> (Date, Double)? in
            ledger.dailyBudget(on: start + step, goal: goal).map { ((start + step).date(in: calendar), $0) }
        }
        // Where the pace changes, marked. The first change is a 29% steepening and the second nearly
        // threefold, so left to the curve alone the first one reads as nothing happening.
        let steps = zip(points, points.dropFirst()).filter {
            Goal.pace(drinking: $0.1 * 7) != Goal.pace(drinking: $1.1 * 7)
        }
        Chart {
            ForEach(steps, id: \.1.0) { _, step in
                RuleMark(x: .value("Date", step.0))
                    .foregroundStyle(Color.dry.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 0) {
                        Text("10%/\(Goal.pace(drinking: step.1 * 7))d")
                            .font(.caption2)
                            .foregroundStyle(Color.dry)
                    }
            }
            ForEach(points, id: \.0) { date, amount in
                AreaMark(x: .value("Date", date), y: .value("Budget", amount))
                    .foregroundStyle(LinearGradient(colors: [Color.dry.opacity(0.4), Color.dry.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", date), y: .value("Budget", amount))
                    .foregroundStyle(Color.dry)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }
        .chartYAxisLabel("u/day")
        .frame(height: 120)
        .padding(.vertical, 6)
    }
}
