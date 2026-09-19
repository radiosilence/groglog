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

private let clock = DayClock(rolloverHour: 5, calendar: london)

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    london.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@MainActor private func container() throws -> ModelContainer {
    try ModelContainer(for: Drink.self, Favourite.self, Pour.self, Day.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

@MainActor private func ledger(_ context: ModelContext) throws -> Ledger {
    Ledger(days: try context.fetch(FetchDescriptor<Day>()), clock: clock)
}

private func beer(abv: Double = 5, ml: Double = 568) -> Drink {
    Drink(name: "Beer", category: .beer, abv: abv, vessel: .pint, volumeMl: ml, price: 5)
}

@Suite struct UnitsTests {
    @Test func pintOfFourPercentIsTwoAndAQuarterUnits() {
        #expect(abs(Units.of(ml: 568, abv: 4) - 2.272) < 0.001)
    }

    @Test func caloriesLandNearDrinkawaresFigures() {
        #expect(abs(Units.kcal(ml: 568, abv: 4, category: .beer) - 182) < 10)
        #expect(abs(Units.kcal(ml: 175, abv: 13, category: .redWine) - 159) < 10)
    }
}

@Suite struct DayKeyTests {
    @Test func roundTripsThroughCivilDates() {
        #expect(DayKey(year: 1970, month: 1, day: 1).number == 0)
        for number in stride(from: -800_000, through: 800_000, by: 997) {
            let c = DayKey(number: number).components
            #expect(DayKey(year: c.year, month: c.month, day: c.day).number == number)
        }
        #expect(DayKey("2026-09-19")?.description == "2026-09-19")
    }

    @Test func knowsWeekdaysAndMonths() {
        #expect(DayKey(year: 2026, month: 9, day: 19).weekday == 7)
        #expect(DayKey(year: 2024, month: 2, day: 10).daysInMonth == 29)
        #expect(DayKey(year: 2026, month: 2, day: 10).daysInMonth == 28)
        #expect(DayKey(year: 2026, month: 9, day: 19).monthStart == DayKey(year: 2026, month: 9, day: 1))
    }
}

@Suite struct DayClockTests {
    @Test func smallHoursBelongToTheNightBefore() {
        #expect(clock.day(for: date(2026, 9, 20, 1, 30)) == DayKey(year: 2026, month: 9, day: 19))
        #expect(clock.day(for: date(2026, 9, 20, 5, 0)) == DayKey(year: 2026, month: 9, day: 20))
    }

    @Test func resolvingATimeLandsWithinTheDrinkingDay() {
        let day = DayKey(year: 2026, month: 9, day: 19)
        #expect(clock.resolve(date(2000, 1, 1, 1, 30), into: day) == date(2026, 9, 20, 1, 30))
        #expect(clock.resolve(date(2000, 1, 1, 21, 0), into: day) == date(2026, 9, 19, 21, 0))
    }

    @Test func weeksStartOnTheCalendarsFirstWeekday() {
        #expect(clock.weekStart(of: DayKey(year: 2026, month: 9, day: 19)) == DayKey(year: 2026, month: 9, day: 14))
    }
}

@MainActor @Suite struct LogbookTests {
    @Test func keepsDayTotalsInStepWithEntries() throws {
        let container = try container()
        let context = container.mainContext
        let logbook = Logbook(context: context, clock: clock)
        let drink = beer()
        context.insert(drink)
        let night = date(2026, 9, 19, 21)

        logbook.log(Serve(drink), at: [night, night.addingTimeInterval(1800), date(2026, 9, 20, 1)])
        let saturday = DayKey(year: 2026, month: 9, day: 19)
        #expect(try ledger(context).totals(on: saturday).count == 3)

        let pours = try context.fetch(Pour.on(saturday...saturday))
        logbook.delete(pours[0])
        logbook.update(pours[1], time: date(2026, 9, 20, 20), vessel: .half, volumeMl: 284, price: 3)
        let after = try ledger(context)
        #expect(after.totals(on: saturday).count == 1)
        #expect(abs(after.totals(on: saturday + 1).units - Units.of(ml: 284, abv: 5)) < 0.0001)

        drink.abv = 4
        logbook.drinkChanged(drink)
        #expect(abs(try ledger(context).totals(on: saturday).units - Units.of(ml: 568, abv: 4)) < 0.0001)
    }

    @Test func dryMarksGiveWayToDrinksAndEmptyDaysDisappear() throws {
        let container = try container()
        let context = container.mainContext
        let logbook = Logbook(context: context, clock: clock)
        let drink = beer()
        context.insert(drink)
        let day = DayKey(year: 2026, month: 9, day: 10)

        logbook.setAlcoholFree(true, on: day)
        #expect(try ledger(context).status(on: day) == .alcoholFree)
        logbook.log(Serve(drink), at: [date(2026, 9, 10, 20)])
        #expect(try ledger(context).status(on: day) == .drank)
        try context.fetch(Pour.on(day...day)).forEach(logbook.delete)
        #expect(try context.fetchCount(FetchDescriptor<Day>()) == 0)
    }

    @Test func rebuildAgreesWithIncrementalUpdates() throws {
        let container = try container()
        let context = container.mainContext
        let logbook = Logbook(context: context, clock: clock)
        let drink = beer()
        context.insert(drink)
        for offset in 0..<20 {
            logbook.log(Serve(drink), at: [date(2026, 8, 1 + offset, 20), date(2026, 8, 1 + offset, 22)])
        }
        let incremental = try context.fetch(FetchDescriptor<Day>(sortBy: [SortDescriptor(\.number)])).map { ($0.number, $0.units, $0.count) }
        logbook.rebuild()
        let rebuilt = try context.fetch(FetchDescriptor<Day>(sortBy: [SortDescriptor(\.number)])).map { ($0.number, $0.units, $0.count) }
        #expect(incremental.elementsEqual(rebuilt) { $0 == $1 })
    }
}

@Suite struct TaperTests {
    let empty = Ledger(days: [], clock: clock)
    let weekly = Goal(isEnabled: true, isDynamic: false, baselineWeekly: 70, reductionPercent: 10, periodDays: 7, start: date(2026, 9, 1), targetWeekly: 14)

    @Test func scheduleCompoundsSmoothlyPerPeriod() throws {
        let start = DayKey(year: 2026, month: 9, day: 1)
        #expect(empty.dailyBudget(on: start, goal: weekly) == 10)
        #expect(abs(try #require(empty.dailyBudget(on: start + 7, goal: weekly)) - 9) < 0.0001)
        let midWeek = try #require(empty.dailyBudget(on: start + 3, goal: weekly))
        #expect(midWeek < 10 && midWeek > 9)
        #expect(empty.dailyBudget(on: start + 800, goal: weekly) == 2)
        #expect(empty.dailyBudget(on: start - 1, goal: weekly) == nil)
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
        goal.start = .now
        let projection = empty.projection(goal: goal)
        #expect((105...109).contains(empty.today.distance(to: try #require(projection.target))))
        #expect((150...156).contains(empty.today.distance(to: try #require(projection.underOneUnit))))
    }
}

@MainActor @Suite struct DynamicBudgetTests {
    @Test func isTheCutOffTheRecentAverage() throws {
        let container = try container()
        let context = container.mainContext
        let logbook = Logbook(context: context, clock: clock)
        let drink = beer(abv: 20, ml: 1000)
        context.insert(drink)
        let today = clock.today
        // Last week: two 20 u days and a dry day; the rest unlogged and left out. Average 13.33, less 10%.
        logbook.log(Serve(drink), at: [clock.start(of: today - 2).addingTimeInterval(15 * 3600), clock.start(of: today - 5).addingTimeInterval(15 * 3600)])
        logbook.setAlcoholFree(true, on: today - 1)
        let goal = Goal(isEnabled: true, isDynamic: true, reductionPercent: 10, periodDays: 7)
        #expect(abs(try #require(try ledger(context).dailyBudget(on: today, goal: goal)) - 12) < 0.0001)
    }

    @Test func looksPastGapsButNotForever() throws {
        let container = try container()
        let context = container.mainContext
        let logbook = Logbook(context: context, clock: clock)
        let drink = beer(abv: 10, ml: 1000)
        context.insert(drink)
        let today = clock.today
        let goal = Goal(isEnabled: true, isDynamic: true, reductionPercent: 10, periodDays: 1)
        #expect(try ledger(context).dailyBudget(on: today, goal: goal) == nil)
        logbook.log(Serve(drink), at: [clock.start(of: today - 40).addingTimeInterval(15 * 3600)])
        #expect(try ledger(context).dailyBudget(on: today, goal: goal) == nil)
        logbook.log(Serve(drink), at: [clock.start(of: today - 5).addingTimeInterval(15 * 3600)])
        #expect(abs(try #require(try ledger(context).dailyBudget(on: today, goal: goal)) - 9) < 0.0001)
    }
}

@MainActor @Suite struct CurveTests {
    @Test func cumulativeStepsUpAtEachDrink() {
        let day = DayKey(year: 2026, month: 9, day: 19)
        let drink = beer()
        let pours = [Pour(drink: drink, at: date(2026, 9, 19, 20), day: day), Pour(drink: drink, at: date(2026, 9, 20, 1), day: day)]
        let points = Ledger(days: [], clock: clock).cumulative(pours, on: day)
        #expect(points.map(\.hour) == [0, 15, 20, 24])
        #expect(abs(points.last!.units - 2 * Units.of(ml: 568, abv: 5)) < 0.001)
    }
}

@MainActor @Suite struct ReferenceTests {
    @Test func loggedDrinksFollowTheirDrinkButKeepTheirPrice() {
        let drink = Drink(name: "Staropramen", category: .beer, abv: 5, vessel: .can, volumeMl: 440, price: 2)
        let day = clock.today
        let usual = Pour(drink: drink, at: .now, day: day)
        let pint = Pour(drink: drink, at: .now, day: day, vessel: .pint, volumeMl: 568)
        drink.name = "Staropramen Premium"
        drink.abv = 4
        drink.price = 3
        #expect(usual.name == "Staropramen Premium" && usual.abv == 4 && pint.vessel == .pint && usual.vessel == .can)
        #expect(abs(pint.units - Units.of(ml: 568, abv: 4)) < 0.0001)
        #expect(usual.price == 2)
        #expect(abs(pint.price - 2 * 568 / 440) < 0.0001)
    }
}

@MainActor @Suite struct BackupTests {
    private func prefs() -> Prefs { Prefs(store: UserDefaults(suiteName: "test-\(UUID())")!) }

    @Test func roundTripsAndIsIdempotent() throws {
        let sourceContainer = try container()
        let source = sourceContainer.mainContext
        let prefs = prefs()
        let logbook = Logbook(context: source, clock: prefs.clock)
        let drink = Drink(name: "Hepcat", category: .beer, abv: 4.6, vessel: .pint, volumeMl: 568)
        source.insert(drink)
        source.insert(Favourite(drink: drink, vessel: .can, volumeMl: 440, price: 3))
        logbook.log(Serve(drink), at: [.now.addingTimeInterval(-3600 * 30)])
        logbook.setAlcoholFree(true, on: prefs.clock.today - 3)
        let data = try Exporter.json(Exporter.backup(context: source, prefs: prefs))

        let targetContainer = try container()
        let target = targetContainer.mainContext
        #expect(try Exporter.restore(data, into: target, prefs: prefs) == 1)
        #expect(try Exporter.restore(data, into: target, prefs: prefs) == 0)
        #expect(try target.fetchCount(FetchDescriptor<Pour>()) == 1)
        let days = try target.fetch(FetchDescriptor<Day>())
        #expect(days.count == 2 && days.filter(\.isAlcoholFree).count == 1)
        let favourite = try #require(try target.fetch(FetchDescriptor<Favourite>()).first)
        #expect(favourite.drink?.name == "Hepcat" && favourite.vessel == .can && favourite.price == 3)
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
        let ledger = Ledger(days: try context.fetch(FetchDescriptor<Day>()), clock: prefs.clock)
        let saturday = DayKey(year: 2026, month: 9, day: 12)
        #expect(abs(ledger.totals(on: saturday).units - 30.6) < 0.001)
        #expect(ledger.totals(on: saturday).kcal == 2696)
        #expect(ledger.status(on: saturday - 1) == .alcoholFree)
    }
}
