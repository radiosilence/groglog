import Foundation

/// Cut units by `reductionPercent` every `periodDays`, compounding smoothly day by day, until the budget reaches `targetWeekly`.
/// "10% a day" and "25% a week" are both just a rate — the budget never steps, it shrinks a little every day.
///
/// With `fromToday` (the default) there's no schedule to fall behind: each day's budget is cut from what was actually
/// drunk recently (see `Ledger.dailyBudget`), so a bad day never turns into a dangerous sudden drop to "catch up".
struct Goal: Codable, Equatable {
    var isEnabled = false
    var fromToday = true
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

    /// When the budget reaches the target, if it's above it to begin with.
    func end(calendar: Calendar = .current) -> Date? {
        guard baselineWeekly > targetWeekly, targetWeekly > 0, reductionPercent > 0 else { return nil }
        let days = log(targetWeekly / baselineWeekly) / log(1 - dailyCut)
        return calendar.date(byAdding: .day, value: Int(days.rounded(.up)), to: calendar.startOfDay(for: start))
    }

    /// The fixed-schedule budget, counted from `start`.
    func scheduledBudget(on day: Date, calendar: Calendar = .current) -> Double? {
        guard isEnabled else { return nil }
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: day)).day ?? 0
        guard elapsed >= 0 else { return nil }
        let weekly = baselineWeekly * pow(1 - dailyCut, Double(elapsed))
        return max(min(targetWeekly, baselineWeekly), weekly) / 7
    }
}
