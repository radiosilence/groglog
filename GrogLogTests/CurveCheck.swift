import Foundation
import Testing
@testable import GrogLog

/// A stepped taper from 30 a day should change pace twice on the way down: 4 days, then 3, then 1.
/// The first change is a 29% steepening and the second a threefold one, so the first is easy to miss
/// on the curve.
@Suite struct SteppedCurveTests {
    @Test func aThirtyADayPlanChangesPaceTwice() throws {
        let calendar = Calendar(identifier: .gregorian)
        let ledger = Ledger(days: [], clock: DayClock(rolloverHour: 5, calendar: calendar))
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let goal = Goal(isEnabled: true, taper: .dynamic, baselineWeekly: 30 * 7, start: start, targetWeekly: 0)
        let first = DayKey(start, in: calendar)

        var paces: [Int] = []
        for step in 0...40 {
            let budget = try #require(ledger.dailyBudget(on: first + step, goal: goal))
            let pace = Goal.pace(drinking: budget * 7)
            if pace != paces.last { paces.append(pace) }
        }
        #expect(paces == [4, 3, 1], "one rung at a time, quickening")
    }
}

/// The stepped taper is solved a rung at a time. Walking it a day at a time is the definition, so the
/// walk lives here and the solution must agree with it across every baseline the picker allows and
/// further out than any taper runs.
@Suite struct SteppedClosedFormTests {
    @Test func agreesWithTheWalkEveryDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let ledger = Ledger(days: [], clock: DayClock(rolloverHour: 5, calendar: calendar))
        let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let first = DayKey(start, in: calendar)
        var mismatches: [String] = []
        for daily in stride(from: 1.0, through: 80, by: 0.5) {
            let goal = Goal(isEnabled: true, taper: .dynamic, baselineWeekly: daily * 7, start: start, targetWeekly: 0)
            var walked = daily
            for step in 0...900 {
                let solved = try #require(ledger.dailyBudget(on: first + step, goal: goal))
                if abs(solved - walked) > max(1e-9, walked * 1e-9) {
                    mismatches.append("\(daily) u/day, day \(step): solved \(solved), walked \(walked)")
                }
                walked *= 1 - Goal.rate(forPace: Goal.pace(drinking: walked * 7))
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(5))")
    }
}
