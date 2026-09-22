import Foundation
import Testing
@testable import GrogLog

/// A stepped taper from 30 a day should change pace twice on the way down — 4 days, then 3, then 1.
/// The first change is a 29% steepening against the second's threefold one, so it's easy to look at
/// the curve and see only one. This says both are there.
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
