import Foundation

/// Cut units by `reductionPercent` every `periodDays`, compounding smoothly day by day, until the budget reaches `targetWeekly`.
/// "10% a day" and "25% a week" are both just a rate — the budget never steps, it shrinks a little every day.
///
/// With `isDynamic` (the default) there's no schedule to fall behind: each day's budget is the cut applied to your
/// average over the previous period, so a bad day never turns into a dangerous sudden drop to "catch up".
/// Otherwise it's a fixed schedule from `baselineWeekly` on `start`. The maths lives in `Ledger`, which has the history.
struct Goal: Codable, Equatable {
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

    /// The equivalent cut per day, for comparing plans on the same footing.
    var dailyCut: Double { 1 - pow(1 - reductionPercent / 100, 1 / Double(max(1, periodDays))) }

    var isFasterThanSafe: Bool { dailyCut > Self.safeDailyCut + 0.0005 }
}
