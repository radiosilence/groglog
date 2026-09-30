import Foundation

/// How the budget comes down.
nonisolated enum Taper: String, Codable, Sendable, CaseIterable {
    /// Ten per cent at a time off a fixed baseline, at the quickest pace the guidance allows for the current
    /// budget, so it quickens as it falls. Shown as "Stepped"; the raw value is persisted, so the case keeps its
    /// original name.
    case dynamic
    /// A share off a fixed baseline. Steep at first, shallow later, and never reaches zero.
    case proportional
    /// The same number of units off every period. Reaches zero on a fixed date, but the share it takes grows
    /// as the budget shrinks, so the last stretch is the sharpest.
    case linear

    var label: String {
        switch self {
        case .dynamic: "Stepped"
        case .proportional: "Proportional"
        case .linear: "Linear"
        }
    }

    /// A one-line description, since the names alone do not explain the behaviour.
    var explanation: String {
        switch self {
        case .dynamic: "Begins at the fastest pace the guidance allows for your current intake, and quickens each time the budget passes a threshold. Progress is slowest at the highest levels."
        case .proportional: "Removes the same percentage each time. It falls quickly at first and more gently as it goes, approaching zero without reaching it."
        case .linear: "Removes the same number of units each time and reaches zero on a fixed date. Each cut becomes a larger share of what remains."
        }
    }
}

/// Brings the budget down until it reaches `targetWeekly`. A proportional taper cuts `reductionPercent` every
/// `periodDays`, compounded smoothly day by day so the budget never steps. A linear taper takes `reductionUnits`
/// off the daily budget over the same period. Dynamic (Stepped) is proportional with the period taken from
/// `ladder` rather than chosen. The maths lives in `Ledger`.
nonisolated struct Goal: Codable, Equatable, Sendable {
    var isEnabled = false
    var taper = Taper.dynamic
    var baselineWeekly = 28.0
    var reductionPercent = Goal.standardCut
    /// How much a linear taper takes off the daily budget each period, in units a day.
    var reductionUnits = 1.0
    /// Ten per cent every four days to begin with, about 2.6% a day. Ten per cent a day is the safe ceiling,
    /// not a suitable starting pace.
    var periodDays = 4
    var start = Date.now
    /// Zero rather than the guideline: most people setting a goal are aiming for none, and an unrequested
    /// floor would stop the budget coming down.
    var targetWeekly = 0.0

    /// Ten per cent a day is the ceiling in the DHSC's UK clinical guidelines for alcohol treatment
    /// (chapter 8, harm reduction, November 2025), the first national guideline to quantify reducing without
    /// medication. The text calls the figure clinical consensus rather than trial evidence, and the protocol
    /// assumes a clinician has judged the person suitable and reviews them throughout. An app can do neither,
    /// so nothing here presents a plan as advice.
    static let safeDailyCut = 0.10

    /// Same guidance: above this, over 65, or in poor health, a person may need to go slower, at no more than
    /// 10% every four days. A new goal starts at that pace.
    static let slowerAboveWeekly = 25 * 7.0

    /// NICE CG115 recommendation 1.3.4.1: over 15 units a day, consider assisted withdrawal.
    static let assistedWithdrawalWeekly = 15 * 7.0

    /// The level below which a taper can end. A proportional taper never reaches zero, so a plan aimed at zero
    /// would have a tail months long. Alcohol services put the point at which a person can simply stop at around
    /// ten units a day, below NICE's threshold for assisted withdrawal. This figure is not in the written
    /// guidance.
    static let stopFrom = 10 * 7.0

    /// NICE CG115 recommendation 1.3.4.5: over 30 units a day, consider inpatient or residential.
    static let inpatientWeekly = 30 * 7.0

    /// The share cut each period. It is fixed at the safe ceiling, so pace is set only by how often the cut
    /// lands: 10% a day at one day apart, about 1.5% a day at a week. No option can then be set too fast,
    /// which a menu of shares would allow.
    static let standardCut = 10.0

    static let periods: [(days: Int, label: String)] = [(1, "day"), (3, "3 days"), (4, "4 days"), (7, "week")]

    /// What a linear taper can take off the daily budget each period. Two units is the maximum: at a day apart
    /// it empties a heavy drinker's budget within a fortnight, and below 20 units a day it already exceeds the
    /// 10% ceiling.
    static let unitCuts = [0.5, 1.0, 1.5, 2.0]

    /// The quickest pace offered above each level, used both to narrow the picker and as the rung a stepped taper
    /// runs at. Over 25 units a day the guidance sets the limit. The rung below is this app's own: NICE considers
    /// assisted withdrawal over 15 a day, and the ceiling was not written for unsupervised reduction at that
    /// level. Under 15 the ceiling applies.
    static let ladder: [(aboveWeekly: Double, pace: Int)] = [
        (slowerAboveWeekly, 4),
        (assistedWithdrawalWeekly, 3),
        (-.infinity, 1),
    ]

    /// `from` is the taper's baseline, which decides the size of its steps. Over 25 units a day the guidance
    /// sets a slower pace of no more than 10% every four days, so the two quicker periods are not offered.
    static func periods(from weekly: Double) -> [(days: Int, label: String)] {
        let floor = ladder.first { weekly > $0.aboveWeekly }!.pace
        let offered = periods.filter { $0.days >= floor }
        return offered.isEmpty ? [periods[periods.count - 1]] : offered
    }

    /// The pace to fall back on when a baseline change removes the chosen one: the quickest still offered, so
    /// raising the baseline slows the taper as little as possible.
    static func nearestOffered(period days: Int, from weekly: Double) -> Int {
        let offered = periods(from: weekly).map(\.days)
        return offered.contains(days) ? days : (offered.min() ?? periods[periods.count - 1].days)
    }

    static func nearestOffered(units: Double, from weekly: Double, perDays days: Int) -> Double {
        let offered = unitCuts(from: weekly, perDays: days)
        return offered.contains(units) ? units : (offered.max() ?? unitCuts[0])
    }

    /// What this takes off the budget on its first day: the steepest step of a proportional taper, and every
    /// step of a linear one.
    func openingDrop(from weekly: Double) -> Double {
        switch taper {
        case .linear: dailyUnitCut
        // Stepped starts on whichever rung its baseline lands it on.
        case .dynamic: weekly / 7 * Self.rate(forPace: Self.pace(drinking: weekly))
        case .proportional: weekly / 7 * dailyCut
        }
    }

    /// The pace a dynamic taper runs at once the budget reaches this level: the quickest offered there, taken
    /// from the same list as the picker so the two cannot disagree.
    static func pace(drinking weekly: Double) -> Int {
        periods(from: weekly).map(\.days).min() ?? periods[periods.count - 1].days
    }

    /// The linear amounts offered. A share scales with intake but a fixed number of units does not: two a day
    /// off a ten-a-day budget is 20%, twice the ceiling, on the first day. Only amounts that open inside the
    /// ceiling are offered; where none do, the smallest is kept so the picker is never empty.
    static func unitCuts(from weekly: Double, perDays days: Int) -> [Double] {
        let ceiling = weekly / 7 * safeDailyCut * Double(max(1, days))
        let offered = unitCuts.filter { $0 <= ceiling + 0.0001 }
        return offered.isEmpty ? [unitCuts.min() ?? 0.5] : offered
    }

    /// The offered period closest in pace to a rate, for a goal saved with a period no longer offered. The
    /// daily rate is matched rather than the number of days, which could make a long taper several times
    /// faster.
    static func nearestPeriod(toDailyCut cut: Double) -> Int {
        periods.map(\.days).min {
            abs(Goal(periodDays: $0).dailyCut - cut) < abs(Goal(periodDays: $1).dailyCut - cut)
        } ?? 1
    }

    /// The daily rate a pace compounds to.
    static func rate(forPace days: Int) -> Double { 1 - pow(1 - standardCut / 100, 1 / Double(max(1, days))) }

    /// The equivalent share per day, for comparing proportional plans on the same footing.
    var dailyCut: Double { 1 - pow(1 - reductionPercent / 100, 1 / Double(max(1, periodDays))) }

    /// Units off the daily budget per day, for a linear plan.
    var dailyUnitCut: Double { reductionUnits / Double(max(1, periodDays)) }

    /// A linear taper takes the same units off whatever the budget, so the share it takes climbs as the
    /// budget falls: it passes the safe rate at this daily budget and is sharper than it from there down.
    var sharpensBelow: Double { dailyUnitCut / Self.safeDailyCut }

    /// Whether to warn about it. The 10%-a-day limit concerns withdrawal from heavy drinking and has no meaning
    /// near the guideline, where warning would contradict the advice on the same screen. The warning applies
    /// only when the taper sharpens while intake is still high.
    func sharpensWhileItMatters(from weekly: Double) -> Bool {
        taper == .linear && weekly >= Self.assistedWithdrawalWeekly && sharpensBelow > Units.weeklyGuideline / 7
    }

    var isFasterThanSafe: Bool {
        switch taper {
        case .dynamic, .proportional: dailyCut > Self.safeDailyCut + 0.0005
        // Safe at the start and too fast at the end, so a single answer would be wrong; `sharpensBelow`
        // gives the crossover.
        case .linear: false
        }
    }

    init(isEnabled: Bool = false, taper: Taper = .dynamic, baselineWeekly: Double = 28,
         reductionPercent: Double = Goal.standardCut, reductionUnits: Double = 1, periodDays: Int = 4,
         start: Date = .now, targetWeekly: Double = 0) {
        self.isEnabled = isEnabled
        self.taper = taper
        self.baselineWeekly = baselineWeekly
        self.reductionPercent = reductionPercent
        self.reductionUnits = reductionUnits
        self.periodDays = periodDays
        self.start = start
        self.targetWeekly = targetWeekly
    }

    /// Every field is optional with a default, so a goal saved by an older build keeps the fields it set.
    /// Synthesised decoding throws on a missing key, and `Prefs` reads the goal with `try?`, so any added field
    /// would silently reset a taper in progress.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Goal()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? fallback.isEnabled
        baselineWeekly = try container.decodeIfPresent(Double.self, forKey: .baselineWeekly) ?? fallback.baselineWeekly
        reductionPercent = try container.decodeIfPresent(Double.self, forKey: .reductionPercent) ?? fallback.reductionPercent
        reductionUnits = try container.decodeIfPresent(Double.self, forKey: .reductionUnits) ?? fallback.reductionUnits
        periodDays = try container.decodeIfPresent(Int.self, forKey: .periodDays) ?? fallback.periodDays
        start = try container.decodeIfPresent(Date.self, forKey: .start) ?? fallback.start
        targetWeekly = try container.decodeIfPresent(Double.self, forKey: .targetWeekly) ?? fallback.targetWeekly
        // Older builds stored the taper as a Bool choosing between dynamic and proportional.
        if let taper = try container.decodeIfPresent(Taper.self, forKey: .taper) {
            self.taper = taper
        } else if let wasDynamic = try decoder.container(keyedBy: Legacy.self).decodeIfPresent(Bool.self, forKey: .isDynamic) {
            taper = wasDynamic ? .dynamic : .proportional
        }
        // A share or period the picker no longer offers would leave it blank, so the goal moves to the offered
        // value nearest its existing pace.
        if !Self.unitCuts.contains(reductionUnits) {
            reductionUnits = Self.unitCuts.min { abs($0 - reductionUnits) < abs($1 - reductionUnits) } ?? 1
        }
        if reductionPercent != Self.standardCut || !Self.periods.contains(where: { $0.days == periodDays }) {
            let pace = dailyCut
            reductionPercent = Self.standardCut
            periodDays = Self.nearestPeriod(toDailyCut: pace)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, taper, baselineWeekly, reductionPercent, reductionUnits, periodDays, start, targetWeekly
    }

    /// Read from older goals only; never written.
    private enum Legacy: String, CodingKey { case isDynamic }
}
