import Foundation
import GRDB
import Testing
@testable import GrogLog

/// Years of heavy logging must not slow down a tap, a screen, or an import. Three years at 20 drinks a day, all of one
/// drink — the worst case for anything that scales with a drink's history.
@Suite struct ScaleTests {
    @Test func threeYearsOfHeavyLoggingStaysFast() throws {
        let database = try AppDatabase.inMemory()
        let clock = DayClock(rolloverHour: 5)
        let logbook = Logbook(writer: database.writer, clock: clock)
        let drink = Drink(name: "Stella Artois", category: .beer, abv: 4.6, vessel: .can, volumeMl: 440)
        logbook.add(drink)
        let today = clock.today

        // A whole history arriving at once, as from a backup: one transaction.
        let bulk = try ContinuousClock().measure {
            try logbook.bulk { db in
                var touched: Set<DayKey> = []
                for offset in 1...(3 * 365) {
                    let day = today - offset
                    let start = clock.start(of: day).addingTimeInterval(12 * 3600)
                    for n in 0..<20 {
                        try Pour(drinkId: drink.id, timestamp: start.addingTimeInterval(Double(n) * 900), day: day.number, vessel: .can, volumeMl: 440, price: 2).insert(db)
                    }
                    touched.insert(day)
                }
                return touched
            }
        }
        #expect(try database.reader.read { try Pour.fetchCount($0) } == 3 * 365 * 20)

        // The common mutations, several times over, timed individually: log, undo, edit.
        var taps: [Duration] = []
        for _ in 0..<5 {
            taps.append(ContinuousClock().measure { logbook.log(Serve(drink), at: [.now]) })
        }
        let todays = try database.reader.read { try EntriesRequest(days: today...today).fetch($0) }
        taps.append(ContinuousClock().measure { logbook.delete(todays[0].pour) })
        taps.append(ContinuousClock().measure { logbook.update(todays[1].pour, time: .now, vessel: .pint, volumeMl: 568, price: 5) })

        // A full screen's worth of reads and maths: every day's totals, budgets, weeks, the day chart's month.
        let screens = try ContinuousClock().measure {
            let ledger = Ledger(days: try database.reader.read { try DaysRequest().fetch($0) }, clock: clock)
            // A year in, so the taper is asked for real: started today, every budget is the baseline and the maths is free.
            let goal = Goal(isEnabled: true, taper: .dynamic, start: clock.start(of: today - 365))
            for offset in 0..<120 { _ = ledger.dailyBudget(on: today - offset, goal: goal) }
            for offset in 0..<28 { for back in 0..<7 { _ = ledger.dailyBudget(on: today - offset - back, goal: goal) } }
            for week in 0..<52 { _ = ledger.week(starting: clock.weekStart(of: today) - 7 * week, goal: goal) }
            _ = ledger.projection(goal: goal)
            _ = ledger.longestDryStreak(in: (today - 365)...today)
            let month = ledger.weekBefore(today)
            let entries = try database.reader.read { try EntriesRequest(days: month.lowerBound...today).fetch($0) }
            _ = ledger.cumulative(entries, on: today)
            _ = ledger.averageCumulative(entries, over: month)
        }

        let rebuild = ContinuousClock().measure { logbook.rebuild() }

        print("scale: bulk \(bulk), taps \(taps.map { $0.formatted(.units(allowed: [.milliseconds])) }), screens \(screens), rebuild \(rebuild)")
        #expect(bulk < .seconds(3))
        #expect(taps.allSatisfy { $0 < .milliseconds(30) })
        #expect(screens < .milliseconds(250))
        #expect(rebuild < .seconds(3))
    }
}
