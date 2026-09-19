import Foundation
import SwiftData
import Testing
@testable import GrogLog

private let london: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    calendar.firstWeekday = 2
    return calendar
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    london.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite struct UnitsTests {
    @Test func pintOfFourPercentIsTwoAndAQuarterUnits() {
        #expect(abs(Units.of(ml: 568, abv: 4) - 2.272) < 0.001)
    }

    @Test func caloriesLandNearDrinkawaresFigures() {
        // Drinkaware: pint of 4% beer ≈ 182 kcal, 175 ml of 13% wine ≈ 159 kcal.
        #expect(abs(Units.kcal(ml: 568, abv: 4, category: .beer) - 182) < 10)
        #expect(abs(Units.kcal(ml: 175, abv: 13, category: .redWine) - 159) < 10)
    }
}

@Suite struct DayClockTests {
    let clock = DayClock(rolloverHour: 5, calendar: london)

    @Test func smallHoursBelongToTheNightBefore() {
        #expect(clock.day(for: date(2026, 9, 20, 1, 30)) == date(2026, 9, 19))
        #expect(clock.day(for: date(2026, 9, 20, 5, 0)) == date(2026, 9, 20))
    }

    @Test func resolvingATimeLandsWithinTheDrinkingDay() {
        let day = date(2026, 9, 19)
        #expect(clock.resolve(date(2000, 1, 1, 1, 30), into: day) == date(2026, 9, 20, 1, 30))
        #expect(clock.resolve(date(2000, 1, 1, 21, 0), into: day) == date(2026, 9, 19, 21, 0))
    }

    @Test func keysAreLocalDates() {
        #expect(clock.key(date(2026, 9, 19)) == "2026-09-19")
        #expect(clock.day(key: "2026-09-19") == date(2026, 9, 19))
    }
}

@MainActor @Suite struct TaperTests {
    let empty = Ledger(pours: [], dryDays: [], clock: DayClock(rolloverHour: 5, calendar: london))
    let weekly = Goal(isEnabled: true, isDynamic: false, baselineWeekly: 70, reductionPercent: 10, periodDays: 7, start: date(2026, 9, 1), targetWeekly: 14)

    @Test func scheduleCompoundsSmoothlyPerPeriod() throws {
        #expect(empty.dailyBudget(on: date(2026, 9, 1), goal: weekly) == 10)
        let aWeekIn = try #require(empty.dailyBudget(on: date(2026, 9, 8), goal: weekly))
        #expect(abs(aWeekIn - 9) < 0.0001)
        let midWeek = try #require(empty.dailyBudget(on: date(2026, 9, 4), goal: weekly))
        #expect(midWeek < 10 && midWeek > 9)
    }

    @Test func holdsAtTheTarget() {
        #expect(empty.dailyBudget(on: date(2028, 1, 1), goal: weekly) == 2)
    }

    @Test func tenPercentADayIsExactlyTheSafeLimit() {
        var daily = weekly
        daily.periodDays = 1
        #expect(!daily.isFasterThanSafe)
        daily.reductionPercent = 25
        #expect(daily.isFasterThanSafe)
    }

    @Test func projectsTargetAndStopDates() throws {
        var goal = weekly
        goal.start = empty.clock.today
        let projection = empty.projection(goal: goal)
        let toTarget = empty.clock.calendar.dateComponents([.day], from: empty.clock.today, to: try #require(projection.target)).day!
        let toStop = empty.clock.calendar.dateComponents([.day], from: empty.clock.today, to: try #require(projection.underOneUnit)).day!
        // 10/day → 2/day at 10%/week ≈ 107 days; → 1/day ≈ 153 days.
        #expect((105...109).contains(toTarget))
        #expect((150...156).contains(toStop))
    }

    @Test func noBudgetBeforeStartOrWhenOff() {
        #expect(empty.dailyBudget(on: date(2026, 8, 31), goal: weekly) == nil)
        var off = weekly
        off.isEnabled = false
        #expect(empty.dailyBudget(on: date(2026, 9, 10), goal: off) == nil)
    }
}

@MainActor @Suite struct LedgerTests {
    let clock = DayClock(rolloverHour: 5, calendar: london)

    private func pour(_ at: Date, ml: Double = 568, abv: Double = 5) -> Pour {
        Pour(drink: Drink(name: "Pint", category: .beer, vessel: .pint, volumeMl: ml, abv: abv, price: 5), at: at)
    }

    @Test func distinguishesDryFromUnlogged() {
        let today = clock.today
        let ledger = Ledger(
            pours: [pour(clock.start(of: clock.adding(-3, to: today)).addingTimeInterval(15 * 3600))],
            dryDays: [AlcoholFreeDay(day: clock.adding(-2, to: today))],
            clock: clock
        )
        #expect(ledger.status(on: clock.adding(-3, to: today)) == .drank)
        #expect(ledger.status(on: clock.adding(-2, to: today)) == .alcoholFree)
        #expect(ledger.status(on: clock.adding(-1, to: today)) == .unlogged)
        #expect(ledger.status(on: clock.adding(-4, to: today)) == .untracked)
        #expect(ledger.status(on: today) == .today)
        #expect(ledger.status(on: clock.adding(1, to: today)) == .future)
    }

    @Test func emptyTodayDoesNotBreakTheDryStreak() {
        let today = clock.today
        let dry = (1...3).map { AlcoholFreeDay(day: clock.adding(-$0, to: today)) }
        #expect(Ledger(pours: [], dryDays: dry, clock: clock).dryStreak() == 3)
    }

    @Test func cumulativeStepsUpAtEachDrink() {
        let day = date(2026, 9, 19)
        let ledger = Ledger(pours: [pour(date(2026, 9, 19, 20)), pour(date(2026, 9, 20, 1))], dryDays: [], clock: clock)
        let points = ledger.cumulative(on: day)
        #expect(points.map(\.hour) == [0, 15, 20, 24])
        #expect(abs(points.last!.units - 2 * Units.of(ml: 568, abv: 5)) < 0.001)
    }

    @Test func dynamicBudgetIsTheCutOffTheRecentAverageNotASchedule() throws {
        let today = clock.today
        let evening = { (daysAgo: Int) in clock.start(of: clock.adding(-daysAgo, to: today)).addingTimeInterval(15 * 3600) }
        // Last week: 20 u, a dry day (0) and 5 u logged; the rest unlogged and left out. Average 8.33, less 10%.
        let ledger = Ledger(
            pours: [pour(evening(2), ml: 1000, abv: 20), pour(evening(5), ml: 500, abv: 10)],
            dryDays: [AlcoholFreeDay(day: clock.adding(-1, to: today))],
            clock: clock
        )
        let goal = Goal(isEnabled: true, isDynamic: true, baselineWeekly: 10, reductionPercent: 10, periodDays: 7, start: clock.adding(-60, to: today))
        let budget = try #require(ledger.dailyBudget(on: today, goal: goal))
        #expect(abs(budget - 7.5) < 0.0001)
    }

    @Test func dynamicBudgetLooksPastGapsButNotForever() throws {
        let today = clock.today
        let evening = { (daysAgo: Int) in clock.start(of: clock.adding(-daysAgo, to: today)).addingTimeInterval(15 * 3600) }
        let goal = Goal(isEnabled: true, isDynamic: true, reductionPercent: 10, periodDays: 1)
        // Last logged five days ago (10 u): budget carries on from there.
        let gap = Ledger(pours: [pour(evening(5), ml: 1000, abv: 10)], dryDays: [], clock: clock)
        #expect(abs(try #require(gap.dailyBudget(on: today, goal: goal)) - 9) < 0.0001)
        // Nothing within four weeks, or nothing at all: no budget rather than a made-up one.
        let stale = Ledger(pours: [pour(evening(40), ml: 1000, abv: 10)], dryDays: [], clock: clock)
        #expect(stale.dailyBudget(on: today, goal: goal) == nil)
        #expect(Ledger(pours: [], dryDays: [], clock: clock).dailyBudget(on: today, goal: goal) == nil)
    }

    @Test func averageLeavesOutUnloggedDays() {
        let ledger = Ledger(
            pours: [pour(date(2026, 9, 18, 20), ml: 1000, abv: 10)],
            dryDays: [AlcoholFreeDay(day: date(2026, 9, 17))],
            clock: clock
        )
        let average = ledger.averageCumulative(of: [date(2026, 9, 16), date(2026, 9, 17), date(2026, 9, 18)])
        #expect(average.last?.units == 5)
    }
}

@MainActor @Suite struct ReferenceTests {
    @Test func loggedDrinksFollowTheirDrinkButKeepTheirPrice() {
        let drink = Drink(name: "Staropramen", category: .beer, vessel: .can, volumeMl: 440, abv: 5, price: 2)
        let usual = Pour(drink: drink, at: .now)
        let pint = Pour(drink: drink, at: .now, volumeMl: 568)
        drink.name = "Staropramen Premium"
        drink.abv = 4
        drink.price = 3
        #expect(usual.name == "Staropramen Premium" && usual.abv == 4)
        #expect(abs(pint.units - Units.of(ml: 568, abv: 4)) < 0.0001)
        #expect(usual.price == 2)
        #expect(abs(pint.price - 2 * 568 / 440) < 0.0001)
    }
}

@MainActor @Suite struct BackupTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Drink.self, Pour.self, AlcoholFreeDay.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func prefs() -> Prefs {
        let suite = "test-\(UUID())"
        return Prefs(store: UserDefaults(suiteName: suite)!)
    }

    @Test func roundTripsAndIsIdempotent() throws {
        let sourceContainer = try container()
        let source = sourceContainer.mainContext
        let prefs = prefs()
        let drink = Drink(name: "Hepcat", category: .beer, vessel: .pint, volumeMl: 568, abv: 4.6, isFavourite: true)
        source.insert(drink)
        source.insert(Pour(drink: drink, at: .now.addingTimeInterval(-3600 * 30)))
        source.insert(AlcoholFreeDay(day: prefs.clock.adding(-3, to: prefs.clock.today)))
        let data = try Exporter.json(Exporter.backup(context: source, prefs: prefs))

        let targetContainer = try container()
        let target = targetContainer.mainContext
        #expect(try Exporter.restore(data, into: target, prefs: prefs) == 1)
        #expect(try Exporter.restore(data, into: target, prefs: prefs) == 0)
        #expect(try target.fetchCount(FetchDescriptor<Pour>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<AlcoholFreeDay>()) == 1)
        #expect(try target.fetch(FetchDescriptor<Drink>()).first?.isFavourite == true)
    }

    @Test func importsDailyTotalsFromAnotherApp() throws {
        let container = try container()
        let context = container.mainContext
        let prefs = prefs()
        let json = """
        {"days": [
            {"date": "2026-09-12", "status": "drank", "units": 30.6, "kcal": 2696, "cost": 42.0},
            {"date": "2026-09-11", "status": "alcohol_free"}
        ]}
        """
        #expect(try Exporter.restore(Data(json.utf8), into: context, prefs: prefs) == 1)
        let pour = try #require(try context.fetch(FetchDescriptor<Pour>()).first)
        #expect(abs(pour.units - 30.6) < 0.001)
        #expect(pour.kcal == 2696)
        #expect(prefs.clock.day(for: pour.timestamp) == prefs.clock.day(key: "2026-09-12"))
        #expect(try context.fetchCount(FetchDescriptor<AlcoholFreeDay>()) == 1)
    }
}
