import Foundation

/// Cut units by `reductionPercent` every `periodDays`, compounding smoothly day by day, until the budget reaches `targetWeekly`.
/// "10% a day" and "25% a week" are both just a rate — the budget never steps, it shrinks a little every day.
///
/// With `isDynamic` (the default) there's no schedule to fall behind: each day's budget is the cut applied to your
/// average over the previous period, so a bad day never turns into a dangerous sudden drop to "catch up".
/// Otherwise it's a fixed schedule from `baselineWeekly` on `start`. The maths lives in `Ledger`, which has the history.
nonisolated struct Goal: Codable, Equatable, Sendable {
    var isEnabled = false
    var isDynamic = true
    var baselineWeekly = 28.0
    var reductionPercent = 10.0
    var periodDays = 7
    var start = Date.now
    var targetWeekly = Units.weeklyGuideline

    /// Faster than this, sudden drops in heavy drinking risk withdrawal; commonly cited self-tapering limit.
    static let safeDailyCut = 0.10
    /// Around 15 units a day, stopping suddenly can be dangerous and assisted withdrawal is advised.
    static let withdrawalRiskWeekly = 105.0

    /// How often the cut lands, and the cuts worth offering over that long. A percentage means something
    /// very different over a day than over twelve weeks: −50% in a week is 9% a day and inside what's
    /// safe, while −50% in a day is half your drinking gone by tomorrow and most of it gone by Friday.
    /// So over a day the offer stops where the safe limit does, and every pairing here is under it.
    static let periods: [(days: Int, label: String)] = [(1, "day"), (7, "week"), (28, "4 wk"), (56, "8 wk"), (84, "12 wk")]

    static func cuts(perDays days: Int) -> [Double] { days == 1 ? [2, 5, 10] : [10, 25, 33, 50] }

    /// The nearest cut this period does offer, for when the period changes under a chosen one.
    static func nearestCut(to percent: Double, perDays days: Int) -> Double {
        cuts(perDays: days).min { abs($0 - percent) < abs($1 - percent) } ?? percent
    }

    /// The equivalent cut per day, for comparing plans on the same footing.
    var dailyCut: Double { 1 - pow(1 - reductionPercent / 100, 1 / Double(max(1, periodDays))) }

    var isFasterThanSafe: Bool { dailyCut > Self.safeDailyCut + 0.0005 }
}
