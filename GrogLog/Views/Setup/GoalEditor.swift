import Charts
import SwiftUI

/// Pick a cut and a timeframe; the budget tapers daily from your recent average to the target.
struct GoalEditor: View {
    let ledger: Ledger
    @Binding var goal: Goal
    @Binding var showingGuidance: Bool

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
                    Button { showingGuidance = true } label: {
                        LabeledContent {
                            HStack(spacing: 4) {
                                Text("10% every \(Goal.periods.first { $0.days == Goal.pace(drinking: from) }?.label ?? "week")")
                                Image(systemName: "info.circle")
                            }
                            .foregroundStyle(Color.grog)
                        } label: {
                            Text("Starts at").foregroundStyle(Color.primary)
                        }
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
                    Label("This is more than 10% a day, which UK treatment guidance sets as the limit for reducing without medication. A slower taper is safer.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.over)
                }
                // The same guidance names 25 units a day as a reason to halve the pace, and NICE gives
                // two thresholds above it where the answer isn't a slower plan but somebody qualified.
                if drinking >= Goal.inpatientWeekly {
                    Label("Over 30 units a day. At this level NICE recommends inpatient or residential withdrawal rather than reducing alone. Please speak to your GP or an alcohol service before you begin.", systemImage: "cross.case.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.over)
                } else if drinking >= Goal.assistedWithdrawalWeekly {
                    Label("Over 15 units a day. At this level NICE recommends considering medically assisted withdrawal. Please consider speaking to your GP or an alcohol service about support.", systemImage: "cross.case")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if drinking > Goal.slowerAboveWeekly {
                    Label("Over 25 units a day, the guidance recommends reducing by no more than 10% every four days, so the faster options are not available.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // The pace in units, which is the thing the percentage hides: a tenth of sixty is six.
                // And when that's why an option has gone, say so rather than leaving a gap.
                let opening = goal.openingDrop(from: from)
                if opening > 0 {
                    Label("That is \(opening.unitsText) u/day less to begin with.", systemImage: "arrow.down.right")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // A linear taper's share grows as the budget shrinks, so the warning isn't yes or no — it's
                // a level, and only one worth naming while it's still above the guideline. It's the size of
                // the cut being warned about, never the amount left, which is the guideline's business.
                if goal.sharpensWhileItMatters(from: from) {
                    Label("The same amount is removed from what remains, so each cut becomes a larger share: below \(goal.sharpensBelow.unitsText) u/day it is more than 10% of what remains each day. Proportional reduces more gently at this point.", systemImage: "exclamationmark.triangle.fill")
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
                    Text("\(amount(goal.baselineWeekly)) → \(amount(goal.targetWeekly)) from \(goal.start.formatted(date: .abbreviated, time: .omitted)). Reduces by 10% every four days above 25 u/day, every three days between 15 and 25, and every day below 15. The pace follows the guidance for the current level rather than being chosen. \(guideline)")
                case .proportional:
                    Text("\(amount(goal.baselineWeekly)) → \(amount(goal.targetWeekly)) from \(goal.start.formatted(date: .abbreviated, time: .omitted)), about \(perDay)% less each day. The cuts become smaller as it goes, so it approaches the target without quite reaching it. \(guideline)")
                case .linear:
                    Text("\(amount(goal.baselineWeekly)) → \(amount(goal.targetWeekly)) from \(goal.start.formatted(date: .abbreviated, time: .omitted)), \(goal.dailyUnitCut.unitsText) u/day less each day. The same amount is removed each time, so it reaches the target on a fixed date. \(guideline)")
                }
            } else {
                Text("Choose a rate of reduction to set a daily and weekly budget.")
            }
        }

        // Guidance treats a gradual reduction as something decided on for a particular person, by
        // someone who has met them. This screen can only count what you've decided; it can't tell you
        // whether a taper is the right approach, and shouldn't be read as saying that it is.
        Section {
            Text("A taper is suitable only when gradual reduction is already the right approach for you. Your GP or an alcohol service can advise on whether it is, and at what pace. GrogLog helps you follow the plan you agree with them.")
        } header: {
            Text("Before you start")
        }

        // DHSC's UK clinical guidelines for alcohol treatment, chapter 8, step 3. These are the signs
        // the guidance says to stop and get help for, not to taper more slowly through.
        Section {
            Label("A fit or seizure", systemImage: "bolt.fill")
            Label("Seeing or hearing things that are not there", systemImage: "eye.trianglebadge.exclamationmark.fill")
            Label("Confusion, or being unsteady on your feet", systemImage: "figure.fall")
        } header: {
            Text("Call 999 if you get any of these")
        } footer: {
            Text("These are signs that withdrawal has become serious. They need emergency care, not a slower reduction.")
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
            if let stop = projection.stoppable {
                Group {
                    if stop <= ledger.today {
                        Text("Already low enough to stop")
                    } else {
                        LabeledContent("Low enough to stop by", value: format(stop))
                    }
                }
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
    @State private var showingGuidance = false

    init(goal: Goal) {
        var draft = goal
        draft.isEnabled = true
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            LedgerReader { ledger in
                Form { GoalEditor(ledger: ledger, goal: $draft, showingGuidance: $showingGuidance) }
            }
            // Outside the Form: a sheet on a Section is copied onto every row, and dismissing one of those
            // copies took the Goal sheet down with it.
            .sheet(isPresented: $showingGuidance) { GuidanceSheet() }
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
        let points = (0...84).compactMap { step -> BudgetPoint? in
            ledger.dailyBudget(on: start + step, goal: goal).map { BudgetPoint(date: (start + step).date(in: calendar), units: $0) }
        }
        // Where the pace changes, marked. The first change is a 29% steepening and the second nearly
        // threefold, so left to the curve alone the first one reads as nothing happening.
        let steps = zip(points, points.dropFirst()).filter {
            Goal.pace(drinking: $0.units * 7) != Goal.pace(drinking: $1.units * 7)
        }.map { PaceStep(date: $1.date, pace: Goal.pace(drinking: $1.units * 7)) }
        BurndownPlot(points: points, steps: steps)
    }
}

private struct BudgetPoint: Equatable {
    let date: Date
    let units: Double
}

private struct PaceStep: Equatable {
    let date: Date
    let pace: Int
}

/// The chart on plain values, so the ledger changing under the sheet doesn't lay it out again.
private struct BurndownPlot: View, Equatable {
    let points: [BudgetPoint]
    let steps: [PaceStep]

    var body: some View {
        Chart {
            ForEach(steps, id: \.date) { step in
                RuleMark(x: .value("Date", step.date))
                    .foregroundStyle(Color.dry.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 0) {
                        Text("10%/\(step.pace)d")
                            .font(.caption2)
                            .foregroundStyle(Color.dry)
                    }
            }
            ForEach(points, id: \.date) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Budget", point.units))
                    .foregroundStyle(LinearGradient(colors: [Color.dry.opacity(0.4), Color.dry.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", point.date), y: .value("Budget", point.units))
                    .foregroundStyle(Color.dry)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
        }
        .chartYAxisLabel("u/day", position: .leading)
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 120)
        .padding(.vertical, 6)
    }
}


/// Where the pace limits come from, and where they don't. Reachable from the pace a stepped taper
/// picks, because that's the number somebody would most want to argue with.
private struct GuidanceSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("No more than 10% a day. This limit comes from the DHSC's UK clinical guidelines for alcohol treatment, published in November 2025, the first national guideline to set a figure for reducing without medication.")
                    Text("The guideline describes this figure as clinical consensus rather than trial evidence, and assumes a clinician has judged the person suitable and reviews their progress.")
                        .foregroundStyle(.secondary)
                    Link("Read chapter 8, harm reduction", destination: URL(string: "https://www.gov.uk/guidance/clinical-guidelines-for-alcohol-treatment/8-harm-reduction")!)
                } header: {
                    Text("The pace")
                }

                Section {
                    Text("Over 25 units a day, the same guidance recommends no more than 10% every four days. It says the same for people over 65 or in poor health.")
                    Text("The step to every three days between 15 and 25 units is GrogLog's own, not the guideline's. NICE recommends considering assisted withdrawal above 15 units a day, and the 10% limit was not written for unsupervised reduction at that level.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Why it starts slower")
                }

                Section {
                    Text("Over 15 units a day, NICE recommends considering medically assisted withdrawal. Over 30, it recommends inpatient or residential care rather than reducing alone.")
                    Link("NICE CG115", destination: URL(string: "https://www.nice.org.uk/guidance/cg115")!)
                } header: {
                    Text("When to ask for help")
                }

                Section {
                    Text("GrogLog does not provide medical advice. It is intended to help you follow a plan agreed with your GP or alcohol service.")
                }
            }
            .navigationTitle("Where this comes from")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
