import Foundation
import GRDB
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

/// A fresh in-memory database with one drink, and a logbook over it.
private func logbook(drink: Drink = beer()) throws -> (Logbook, Drink) {
    let database = try AppDatabase.inMemory()
    let logbook = Logbook(writer: database.writer, clock: clock)
    try database.writer.write { try drink.insert($0) }
    return (logbook, drink)
}

private func ledger(_ logbook: Logbook) throws -> Ledger {
    Ledger(days: try logbook.writer.read { try Day.fetchAll($0) }, clock: clock)
}

private func entries(_ logbook: Logbook, _ days: ClosedRange<DayKey>) throws -> [Entry] {
    try logbook.writer.read { try EntriesRequest(days: days).fetch($0) }
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

    @Test func theRolloverHoldsOnTheNightsTheClocksChange() {
        // Back an hour on 25 October, forward on 29 March: 04:30 is still last night, 05:30 is already today.
        #expect(clock.day(for: date(2026, 10, 25, 4, 30)) == DayKey(year: 2026, month: 10, day: 24))
        #expect(clock.day(for: date(2026, 3, 29, 5, 30)) == DayKey(year: 2026, month: 3, day: 29))
        for day in [DayKey(year: 2026, month: 10, day: 25), DayKey(year: 2026, month: 3, day: 29)] {
            #expect(clock.day(for: clock.start(of: day)) == day)
            #expect(clock.day(for: clock.start(of: day).addingTimeInterval(-60)) == day - 1)
        }
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

@Suite struct LogbookTests {
    @Test func keepsDayTotalsInStepWithEntries() throws {
        var (logbook, drink) = try logbook()
        let night = date(2026, 9, 19, 21)
        logbook.log(Serve(drink), at: [night, night.addingTimeInterval(1800), date(2026, 9, 20, 1)])
        let saturday = DayKey(year: 2026, month: 9, day: 19)
        #expect(try ledger(logbook).totals(on: saturday).count == 3)

        let pours = try entries(logbook, saturday...saturday).map(\.pour)
        logbook.delete(pours[0])
        logbook.update(pours[1], time: date(2026, 9, 20, 20), vessel: .half, volumeMl: 284, price: 3)
        let after = try ledger(logbook)
        #expect(after.totals(on: saturday).count == 1)
        #expect(abs(after.totals(on: saturday + 1).units - Units.of(ml: 284, abv: 5)) < 0.0001)

        drink.abv = 4
        logbook.save(drink)
        #expect(abs(try ledger(logbook).totals(on: saturday).units - Units.of(ml: 568, abv: 4)) < 0.0001)
    }

    @Test func dryMarksGiveWayToDrinksAndEmptyDaysDisappear() throws {
        let (logbook, drink) = try logbook()
        let day = DayKey(year: 2026, month: 9, day: 10)
        logbook.setAlcoholFree(true, on: day)
        #expect(try ledger(logbook).status(on: day) == .alcoholFree)
        logbook.log(Serve(drink), at: [date(2026, 9, 10, 20)])
        #expect(try ledger(logbook).status(on: day) == .drank)
        try entries(logbook, day...day).forEach { logbook.delete($0.pour) }
        #expect(try logbook.writer.read { try Day.fetchCount($0) } == 0)
    }

    @Test func handSetSpendStandsUntilCleared() throws {
        let (logbook, drink) = try logbook()
        let day = DayKey(year: 2026, month: 9, day: 19)
        logbook.log(Serve(drink), at: [date(2026, 9, 19, 20), date(2026, 9, 19, 22)])
        #expect(try ledger(logbook).totals(on: day).cost == 10)

        logbook.setSpend(42, on: day)
        #expect(try ledger(logbook).totals(on: day).cost == 42)
        #expect(try ledger(logbook).derivedSpend(on: day) == 10)

        // Another round, and a rebuild, leave it standing.
        logbook.log(Serve(drink), at: [date(2026, 9, 19, 23)])
        logbook.rebuild()
        #expect(try ledger(logbook).totals(on: day).cost == 42)
        #expect(try ledger(logbook).derivedSpend(on: day) == 15)

        logbook.setSpend(nil, on: day)
        #expect(try ledger(logbook).spendOverride(on: day) == nil)
        #expect(try ledger(logbook).totals(on: day).cost == 15)
    }

    @Test func aSpendOnItsOwnIsntADrinkingDay() throws {
        let (logbook, _) = try logbook()
        let day = DayKey(year: 2026, month: 9, day: 1)
        logbook.setSpend(20, on: day)
        let after = try ledger(logbook)
        #expect(after.totals(on: day).cost == 20)
        #expect(!after.isLogged(day))
        logbook.setSpend(nil, on: day)
        #expect(try logbook.writer.read { try Day.fetchCount($0) } == 0)
    }

    @Test func rebuildAgreesWithIncrementalUpdates() throws {
        let (logbook, drink) = try logbook()
        for offset in 0..<20 {
            logbook.log(Serve(drink), at: [date(2026, 8, 1 + offset, 20), date(2026, 8, 1 + offset, 22)])
        }
        logbook.setAlcoholFree(true, on: DayKey(year: 2026, month: 8, day: 25))
        let incremental = try logbook.writer.read { try Day.order(Column("number")).fetchAll($0) }
        logbook.rebuild()
        #expect(try logbook.writer.read { try Day.order(Column("number")).fetchAll($0) } == incremental)
    }

    @Test func loggedDrinksHaveNoDeleteButCanBeHidden() throws {
        let (logbook, drink) = try logbook()
        logbook.log(Serve(drink), at: [.now])
        #expect(throws: (any Error).self) { try logbook.writer.write { _ = try drink.delete($0) } }
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
        // Started today — by the clock, not the calendar: before 5am `.now` is still yesterday's drinking day.
        goal.start = clock.start(of: empty.today)
        let projection = empty.projection(goal: goal)
        #expect((105...109).contains(empty.today.distance(to: try #require(projection.target))))
        #expect((150...156).contains(empty.today.distance(to: try #require(projection.underOneUnit))))
    }
}

@Suite struct DynamicBudgetTests {
    @Test func isTheCutOffTheRecentAverage() throws {
        let (logbook, drink) = try logbook(drink: beer(abv: 20, ml: 1000))
        let today = clock.today
        // Last week: two 20 u days and a dry day; the rest unlogged and left out. Average 13.33, less 10%.
        logbook.log(Serve(drink), at: [clock.start(of: today - 2).addingTimeInterval(15 * 3600), clock.start(of: today - 5).addingTimeInterval(15 * 3600)])
        logbook.setAlcoholFree(true, on: today - 1)
        let goal = Goal(isEnabled: true, isDynamic: true, reductionPercent: 10, periodDays: 7)
        #expect(abs(try #require(try ledger(logbook).dailyBudget(on: today, goal: goal)) - 12) < 0.0001)
    }

    @Test func looksPastGapsButNotForever() throws {
        let (logbook, drink) = try logbook(drink: beer(abv: 10, ml: 1000))
        let today = clock.today
        let goal = Goal(isEnabled: true, isDynamic: true, reductionPercent: 10, periodDays: 1)
        #expect(try ledger(logbook).dailyBudget(on: today, goal: goal) == nil)
        logbook.log(Serve(drink), at: [clock.start(of: today - 40).addingTimeInterval(15 * 3600)])
        #expect(try ledger(logbook).dailyBudget(on: today, goal: goal) == nil)
        logbook.log(Serve(drink), at: [clock.start(of: today - 5).addingTimeInterval(15 * 3600)])
        #expect(abs(try #require(try ledger(logbook).dailyBudget(on: today, goal: goal)) - 9) < 0.0001)
    }
}

@Suite struct CurveTests {
    @Test func cumulativeStepsUpAtEachDrink() {
        let day = DayKey(year: 2026, month: 9, day: 19)
        let drink = beer()
        let entries = [date(2026, 9, 19, 20), date(2026, 9, 20, 1)].map {
            Entry(pour: Pour(drinkId: drink.id, timestamp: $0, day: day.number, vessel: .pint, volumeMl: 568, price: 5), drink: drink)
        }
        let points = Ledger(days: [], clock: clock).cumulative(entries, on: day)
        #expect(points.map(\.x) == [0, 15, 20, 24])
        #expect(abs(points.last!.units - 2 * Units.of(ml: 568, abv: 5)) < 0.001)
    }

    /// The week line is rolled flat over three hours, which must not cost it the two things that make it a
    /// running total: it only ever rises, and it ends on the week's mean.
    @Test func theWeekAverageIsSmoothedButStillARunningTotal() {
        let day = DayKey(year: 2026, month: 9, day: 20)
        let week = (day - 7)...(day - 1)
        let drink = beer()
        // A pint on two of the seven days, hours apart, so an unsmoothed mean would step twice. The other
        // five are alcohol-free, so all seven count and the mean lands on two pints across seven days.
        let drinking = [DayKey(year: 2026, month: 9, day: 14), DayKey(year: 2026, month: 9, day: 18)]
        let entries = zip(drinking, [date(2026, 9, 14, 19), date(2026, 9, 18, 22)]).map { when, at in
            Entry(pour: Pour(drinkId: drink.id, timestamp: at, day: when.number, vessel: .pint, volumeMl: 568, price: 5), drink: drink)
        }
        let wet = Set(drinking.map(\.number))
        let rows = week.map { Day(number: $0.number, isAlcoholFree: !wet.contains($0.number), count: wet.contains($0.number) ? 1 : 0) }
        let points = Ledger(days: rows, clock: clock).averageCumulative(entries, over: week)
        #expect(!points.isEmpty)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.units <= $1.units + 0.000_1 })
        #expect(abs(points.last!.units - 2 * Units.of(ml: 568, abv: 5) / 7) < 0.001)
        #expect(points.first!.units == 0)
    }
}

@Suite struct ReferenceTests {
    @Test func entriesFollowTheirDrinkButKeepTheirSizeAndPrice() throws {
        var (logbook, drink) = try logbook(drink: Drink(name: "Staropramen", category: .beer, abv: 5, vessel: .can, volumeMl: 440, price: 2))
        logbook.log(Serve(drink), at: [.now])
        logbook.log(Serve(drink, .pint, 568), at: [.now])
        drink.name = "Staropramen Premium"
        drink.abv = 4
        drink.price = 3
        logbook.save(drink)
        let today = clock.day(for: .now)
        let logged = try entries(logbook, today...today)
        #expect(logged.allSatisfy { $0.name == "Staropramen Premium" && $0.abv == 4 })
        #expect(logged.map(\.vessel) == [.can, .pint])
        #expect(logged[0].price == 2)
        #expect(abs(logged[1].price - 2 * 568 / 440) < 0.0001)
    }
}

@MainActor @Suite struct BackupTests {
    private func prefs() -> Prefs { Prefs(store: UserDefaults(suiteName: "test-\(UUID())")!) }

    @Test func roundTripsAndIsIdempotent() throws {
        let prefs = prefs()
        let source = try AppDatabase.inMemory()
        let logbook = Logbook(writer: source.writer, clock: prefs.clock)
        let drink = Drink(name: "Hepcat", category: .beer, abv: 4.6, vessel: .pint, volumeMl: 568)
        logbook.add(drink)
        logbook.pin(Serve(drink, .can, 440, price: 3))
        logbook.log(Serve(drink), at: [.now.addingTimeInterval(-3600 * 30)])
        logbook.setAlcoholFree(true, on: prefs.clock.today - 3)
        let settings = Exporter.Settings(prefs)
        let data = try Exporter.json(try source.reader.read { try Exporter.backup($0, settings: settings) })

        let target = try AppDatabase.inMemory()
        #expect(try Exporter.restore(data, writer: target.writer, prefs: prefs) == 1)
        #expect(try Exporter.restore(data, writer: target.writer, prefs: prefs) == 0)
        try target.reader.read { db in
            #expect(try Pour.fetchCount(db) == 1)
            let days = try Day.fetchAll(db)
            #expect(days.count == 2 && days.filter(\.isAlcoholFree).count == 1)
            #expect(try Favourite.fetchCount(db) == 2)
            #expect(try Favourite.filter(Column("vessel") == "can").fetchOne(db)?.price == 3)
        }
    }

    @Test func restoringOntoAFreshInstallDoesntDoubleDrinks() throws {
        let prefs = prefs()
        let source = try AppDatabase.inMemory()
        let logbook = Logbook(writer: source.writer, clock: prefs.clock)
        try Seed.drinksIfNeeded(logbook)
        let beer = try #require(try source.reader.read { try Drink.filter(Column("name") == "Beer").fetchOne($0) })
        logbook.log(Serve(beer), at: [.now])
        let settings = Exporter.Settings(prefs)
        let data = try Exporter.json(try source.reader.read { try Exporter.backup($0, settings: settings) })

        let (drinks, favourites) = try source.reader.read { (try Drink.fetchCount($0), try Favourite.fetchCount($0)) }

        let fresh = try AppDatabase.inMemory()
        try Seed.drinksIfNeeded(Logbook(writer: fresh.writer, clock: prefs.clock))
        try Exporter.restore(data, writer: fresh.writer, prefs: prefs)
        let restored = try fresh.reader.read { db in
            (try Drink.fetchCount(db), try Favourite.fetchCount(db), try Pour.including(required: Pour.drink).fetchCount(db))
        }
        #expect(restored.0 == drinks && restored.1 == favourites && restored.2 == 1)
    }

    @Test func importsDailyTotalsFromAnotherApp() throws {
        let prefs = prefs()
        let database = try AppDatabase.inMemory()
        let json = """
        {"days": [
            {"date": "2026-09-12", "status": "drank", "units": 30.6, "kcal": 2696, "cost": 42.0},
            {"date": "2026-09-11", "status": "alcohol_free"}
        ]}
        """
        #expect(try Exporter.restore(Data(json.utf8), writer: database.writer, prefs: prefs) == 1)
        let ledger = Ledger(days: try database.reader.read { try Day.fetchAll($0) }, clock: prefs.clock)
        let saturday = DayKey(year: 2026, month: 9, day: 12)
        #expect(abs(ledger.totals(on: saturday).units - 30.6) < 0.001)
        #expect(ledger.totals(on: saturday).kcal == 2696)
        #expect(ledger.status(on: saturday - 1) == .alcoholFree)
    }
}

/// The catalogue is a hand-written table, so guard the mistakes hand-writing makes: a stray decimal point,
/// a brand listed twice, a serve with no size.
@Suite struct CatalogTests {
    /// What a strength can plausibly be for each kind of drink — wide enough for Żywiec Porter and
    /// Wray & Nephew, tight enough to catch 45% where 4.5% was meant.
    private func band(_ category: DrinkCategory) -> ClosedRange<Double> {
        switch category {
        case .beer, .stout: 2...13
        case .cider: 2...9
        case .redWine, .whiteWine, .rose: 8...16
        case .bubbles: 5...14
        case .fortified: 12...22
        case .spirit: 10...85
        case .alcopop: 3...8
        case .cocktail: 3...35
        case .units: 100...100
        }
    }

    @Test func strengthsArePlausibleForTheirKind() {
        for brand in Catalog.brands {
            #expect(band(brand.category).contains(brand.abv), "\(brand.name) at \(brand.abv)%")
        }
    }

    @Test func everyBrandIsListedOnceAndHasSizes() {
        #expect(Set(Catalog.brands.map(\.name)).count == Catalog.brands.count)
        #expect(Set(Catalog.items.map(\.id)).count == Catalog.items.count)
        #expect(Catalog.brands.allSatisfy { !$0.serves.isEmpty })
        // The ceiling is a white cider bottle, the one serve that isn't a glassful.
        #expect(Catalog.items.allSatisfy { $0.volumeMl >= 10 && $0.volumeMl <= 2500 })
    }

    @Test func searchFindsBrandsAndKinds() {
        #expect(Catalog.search("stella").contains { $0.name == "Stella Artois" })
        #expect(Catalog.search("Red wine").allSatisfy { $0.category == .redWine })
        #expect(Catalog.search("  ").isEmpty)
    }
}

/// The `pour` table is the only one that grows without bound — a row per drink, forever. Everything else is
/// a few hundred rows at most, where a scan costs nothing and an index would only slow the writes. So this
/// checks the two that matter are there, and that SQLite actually reaches for them.
@Suite struct IndexTests {
    private func database() throws -> AppDatabase { try AppDatabase.inMemory() }

    @Test func pourIsIndexedOnTheColumnsItIsQueriedBy() throws {
        let indexed = try database().writer.read { db in
            try db.indexes(on: "pour").flatMap(\.columns)
        }
        #expect(indexed.contains("day"))
        #expect(indexed.contains("drinkId"))
    }

    @Test func theDayRangeAndTheDrinkLookupBothUseAnIndex() throws {
        let plans = try database().writer.read { db -> [String] in
            try [Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN SELECT * FROM pour WHERE day BETWEEN 1 AND 7"),
                 Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN SELECT COUNT(*) FROM pour WHERE drinkId = x'00'")]
                .map { $0.map { $0["detail"] as String? ?? "" }.joined(separator: " ") }
        }
        // "USING COVERING INDEX" counts — it's the better plan, not a different one.
        #expect(plans.allSatisfy { $0.contains("SEARCH pour USING") }, "\(plans)")
        #expect(!plans.contains { $0.contains("SCAN pour") }, "\(plans)")
    }
}
