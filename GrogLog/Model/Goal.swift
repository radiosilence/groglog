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
    var reductionPercent = 10.0
    /// How much a linear taper takes off the *daily* budget each period, in units a day.
    var reductionUnits = 1.0
    /// 10% a day to begin with: the fastest taper that isn't faster than is safe.
    var periodDays = 1
    var start = Date.now
    /// Nought, not the guideline. Someone opening this is more likely to be heading for none than for
    /// fourteen a week, and a floor you didn't ask for is a floor that stops the budget coming down.
    var targetWeekly = 0.0

    /// Faster than this, sudden drops in heavy drinking risk withdrawal; commonly cited self-tapering limit.
    static let safeDailyCut = 0.10
    /// Around 15 units a day, stopping suddenly can be dangerous and assisted withdrawal is advised.
    static let withdrawalRiskWeekly = 105.0

    /// How often the cut lands, and the shares worth offering over that long. A percentage means something
    /// very different over a day than over twelve weeks: −50% in a week is 9% a day and inside what's
    /// safe, while −50% in a day is half your drinking gone by tomorrow and most of it gone by Friday.
    /// So over a day the offer stops where the safe limit does, and every pairing here is under it.
    static let periods: [(days: Int, label: String)] = [(1, "day"), (7, "week"), (28, "4 wk"), (56, "8 wk"), (84, "12 wk")]

    static func cuts(perDays days: Int) -> [Double] { days == 1 ? [2, 5, 10] : [10, 25, 33, 50] }

    /// The nearest share this period does offer, for when the period changes under a chosen one.
    static func nearestCut(to percent: Double, perDays days: Int) -> Double {
        cuts(perDays: days).min { abs($0 - percent) < abs($1 - percent) } ?? percent
    }

    /// The equivalent share per day, for comparing proportional plans on the same footing.
    var dailyCut: Double { 1 - pow(1 - reductionPercent / 100, 1 / Double(max(1, periodDays))) }

    /// Units off the daily budget per day, for a linear plan.
    var dailyUnitCut: Double { reductionUnits / Double(max(1, periodDays)) }

    /// A linear taper takes the same units off whatever the budget, so the share it takes climbs as the
    /// budget falls: it passes the safe rate at this daily budget and is sharper than it from there down.
    var sharpensBelow: Double { dailyUnitCut / Self.safeDailyCut }

    var isFasterThanSafe: Bool {
        switch taper {
        case .dynamic, .proportional: dailyCut > Self.safeDailyCut + 0.0005
        // Never at the top and always at the bottom, so a single yes or no would be a lie either way.
        // `sharpensBelow` says where it turns, which is what there is to say.
        case .linear: false
        }
    }

    init(isEnabled: Bool = false, taper: Taper = .dynamic, baselineWeekly: Double = 28,
         reductionPercent: Double = 10, reductionUnits: Double = 1, periodDays: Int = 1,
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
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, taper, baselineWeekly, reductionPercent, reductionUnits, periodDays, start, targetWeekly
    }

    /// Kept only so an older goal can still be read; nothing writes it.
    private enum Legacy: String, CodingKey { case isDynamic }
}
