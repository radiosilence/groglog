import Foundation

/// How the budget comes down.
nonisolated enum Taper: String, Codable, Sendable, CaseIterable {
    /// A share off your own recent average, so there's no schedule to fall behind and a bad day never
    /// becomes a sudden drop to catch up with.
    case dynamic
    /// A share off a fixed baseline. Steep at the top, shallow at the bottom, and never quite nothing.
    case proportional
    /// The same number of units off every period. Lands on nothing on a date you can name — but the
    /// share it takes grows as the budget shrinks, so the last stretch is the sharpest.
    case linear

    var label: String {
        switch self {
        case .dynamic: "Dynamic"
        case .proportional: "Proportional"
        case .linear: "Linear"
        }
    }
}

/// Bring the budget down until it reaches `targetWeekly`, by one of three tapers. A proportional taper
/// cuts `reductionPercent` every `periodDays`, compounding smoothly day by day — "10% a day" and "25% a
/// week" are both just a rate, and the budget never steps. A linear one takes `reductionUnits` off the
/// daily budget over that same period instead. Dynamic is proportional against your own recent average
/// rather than a baseline. The maths lives in `Ledger`, which has the history.
nonisolated struct Goal: Codable, Equatable, Sendable {
    var isEnabled = false
    var taper = Taper.dynamic
    var baselineWeekly = 28.0
    var reductionPercent = Goal.standardCut
    /// How much a linear taper takes off the *daily* budget each period, in units a day.
    var reductionUnits = 1.0
    /// Ten per cent every four days to begin with — about 2.6% a day. Ten a day is the fastest that
    /// isn't unsafe, which is not the same as the one to start somebody on.
    var periodDays = 4
    var start = Date.now
    /// Nought, not the guideline. Someone opening this is more likely to be heading for none than for
    /// fourteen a week, and a floor you didn't ask for is a floor that stops the budget coming down.
    var targetWeekly = 0.0

    /// Ten per cent a day is the ceiling in the DHSC's UK clinical guidelines for alcohol treatment
    /// (chapter 8, harm reduction, November 2025) — the first national guideline to put a number on
    /// reducing without medication. Its own text calls that number the development group's clinical
    /// consensus rather than trial evidence, and the protocol around it assumes a clinician has judged
    /// the person suitable and reviews them as they go. An app can't do either, which is why nothing
    /// here presents a plan as advice.
    static let safeDailyCut = 0.10

    /// The same guidance: someone over this, or over 65, or in poor health, may need to go slower, and
    /// suggests no more than 10% every four days — which is where a new goal starts.
    static let slowerAboveWeekly = 25 * 7.0

    /// NICE CG115 recommendation 1.3.4.1: over 15 units a day, consider assisted withdrawal.
    static let assistedWithdrawalWeekly = 15 * 7.0

    /// NICE CG115 recommendation 1.3.4.5: over 30 units a day, consider inpatient or residential.
    static let inpatientWeekly = 30 * 7.0

    /// How often the cut lands. The share itself doesn't move: ten per cent is the fastest rate that
    /// isn't faster than is safe, so taking it more or less often is the whole of the pace. A day apart
    /// it's 10% a day, a week apart 1.5% — and nothing in that range can be set too fast, which a menu
    /// of shares could be. −50% is fine over a week and 20% a day over three.
    static let standardCut = 10.0

    static let periods: [(days: Int, label: String)] = [(1, "day"), (3, "3 days"), (4, "4 days"), (7, "week")]

    /// What a linear taper can take off the daily budget each period. Two units is the top of it: a day
    /// apart that's 2 u/day off every day, which empties a heavy drinker's budget inside a fortnight and
    /// is already taking more than a tenth of what's left below 20 u/day.
    static let unitCuts = [0.5, 1.0, 1.5, 2.0]

    /// The most a taper may take off on its first morning, which is the steepest step it ever takes.
    /// Not a figure from the guidance — that caps the share and lengthens the period instead — but ten
    /// per cent of sixty units is six of them gone overnight, and withholding the quicker paces from
    /// whoever is drinking most is the guidance's own answer to that. This withholds them by the size
    /// of the step rather than the size of the drinking, which catches the same thing from the other
    /// side. Nothing is reshaped by it: a pace is offered or it isn't, and the screen says why.
    static let maxOpeningDrop = 2.0

    /// Which periods to offer somebody drinking this much. Over 25 units a day the guidance names a
    /// slower pace for exactly that reason — no more than 10% every four days — so the quicker two
    /// aren't on the table. On top of that, nothing whose first step is over two units. A taper is
    /// still on offer either way, at a pace that suits how much is being drunk.
    static func periods(drinking weekly: Double) -> [(days: Int, label: String)] {
        let offered = periods.filter { period in
            guard weekly <= slowerAboveWeekly || period.days >= 4 else { return false }
            return weekly / 7 * Goal(periodDays: period.days).dailyCut <= maxOpeningDrop + 0.0001
        }
        return offered.isEmpty ? [periods[periods.count - 1]] : offered
    }

    /// What this takes off the budget on its first day — the steepest step a proportional taper makes,
    /// and every step a linear one makes.
    func openingDrop(drinking weekly: Double) -> Double {
        taper == .linear ? dailyUnitCut : weekly / 7 * dailyCut
    }

    /// And which linear amounts. A share is self-limiting — ten per cent is ten per cent of whatever
    /// you drink — but a fixed number of units isn't: two a day off a ten-a-day budget is twenty per
    /// cent, twice the ceiling, on the first morning.
    ///
    /// That only matters where withdrawal does. NICE puts assisted withdrawal at over 15 units a day
    /// and calls milder dependence than that no case for it, so under the same figure the ceiling has
    /// nothing to bite on and every amount stands. A rate limit meant for withdrawal, applied where
    /// withdrawal isn't the risk, is the same mistake as warning somebody off the guideline.
    static func unitCuts(drinking weekly: Double, perDays days: Int) -> [Double] {
        guard weekly >= assistedWithdrawalWeekly else { return unitCuts }
        let ceiling = weekly / 7 * safeDailyCut * Double(max(1, days))
        let offered = unitCuts.filter { $0 <= ceiling + 0.0001 }
        return offered.isEmpty ? [unitCuts.min() ?? 0.5] : offered
    }

    /// The offered period closest in pace to a rate, for a goal saved when the picker offered others.
    /// It's the daily rate that's matched, not the number of days — snapping an eight-week taper to the
    /// nearest period it still has would quietly make it several times faster.
    static func nearestPeriod(toDailyCut cut: Double) -> Int {
        periods.map(\.days).min {
            abs(Goal(periodDays: $0).dailyCut - cut) < abs(Goal(periodDays: $1).dailyCut - cut)
        } ?? 1
    }

    /// The equivalent share per day, for comparing proportional plans on the same footing.
    var dailyCut: Double { 1 - pow(1 - reductionPercent / 100, 1 / Double(max(1, periodDays))) }

    /// Units off the daily budget per day, for a linear plan.
    var dailyUnitCut: Double { reductionUnits / Double(max(1, periodDays)) }

    /// A linear taper takes the same units off whatever the budget, so the share it takes climbs as the
    /// budget falls: it passes the safe rate at this daily budget and is sharper than it from there down.
    var sharpensBelow: Double { dailyUnitCut / Self.safeDailyCut }

    /// Whether that's worth saying. The 10%-a-day limit is about withdrawal from heavy drinking, so it
    /// stops meaning anything as the budget nears the guideline — cutting from a unit and a half to none
    /// carries no risk, and warning about it would contradict the guideline the same screen recommends.
    /// Worth a word only where the taper sharpens while there's still enough drinking for it to matter.
    func sharpensWhileItMatters(drinking weekly: Double) -> Bool {
        taper == .linear && weekly >= Self.assistedWithdrawalWeekly && sharpensBelow > Units.weeklyGuideline / 7
    }

    var isFasterThanSafe: Bool {
        switch taper {
        case .dynamic, .proportional: dailyCut > Self.safeDailyCut + 0.0005
        // Never at the top and always at the bottom, so a single yes or no would be a lie either way.
        // `sharpensBelow` says where it turns, which is what there is to say.
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

    /// Every field optional with the default behind it, so a goal saved by an older build keeps whatever
    /// it did set. Synthesised decoding throws on a key that didn't exist yet, and `Prefs` reads the goal
    /// with `try?` — so one added field would have quietly reset a taper somebody was part-way through.
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
        // Before there was a third way to taper this was a yes-or-no between dynamic and proportional.
        if let taper = try container.decodeIfPresent(Taper.self, forKey: .taper) {
            self.taper = taper
        } else if let wasDynamic = try decoder.container(keyedBy: Legacy.self).decodeIfPresent(Bool.self, forKey: .isDynamic) {
            taper = wasDynamic ? .dynamic : .proportional
        }
        // A share or a period the picker has since dropped would leave it showing nothing, so the goal
        // moves to the offered period nearest the pace it was already going — same taper, said anew.
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

    /// Kept only so an older goal can still be read; nothing writes it.
    private enum Legacy: String, CodingKey { case isDynamic }
}
