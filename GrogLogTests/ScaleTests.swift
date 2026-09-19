import Foundation
import SwiftData
import Testing
@testable import GrogLog

/// Years of heavy logging must not slow down a tap or a screen: logging touches one day, and screens read day totals.
/// Three years at 20 drinks a day, all of one drink — the worst case for anything that scales with a drink's history.
@MainActor @Suite struct ScaleTests {
    @Test func threeYearsOfHeavyLoggingStaysFast() throws {
        let container = try ModelContainer(for: Drink.self, Favourite.self, Pour.self, Day.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let clock = DayClock(rolloverHour: 5)
        let drink = Drink(name: "Stella Artois", category: .beer, abv: 4.6, vessel: .can, volumeMl: 440)
        context.insert(drink)
        let today = clock.today
        let setup = ContinuousClock().measure {
            for offset in 1...(3 * 365) {
                let day = today - offset
                let start = clock.start(of: day).addingTimeInterval(12 * 3600)
                for n in 0..<20 { context.insert(Pour(drink: drink, at: start.addingTimeInterval(Double(n) * 900), day: day)) }
                if offset.isMultiple(of: 30) { try? context.save() }
            }
        }
        let logbook = Logbook(context: context, clock: clock)
        logbook.rebuild()
        #expect(try context.fetchCount(FetchDescriptor<Pour>()) == 3 * 365 * 20)

        // The common mutations, several times over, timed individually: log, undo, edit.
        var taps: [Duration] = []
        for _ in 0..<5 {
            taps.append(ContinuousClock().measure { logbook.log(Serve(drink), at: [.now]) })
        }
        let todays = try context.fetch(Pour.on(today...today))
        taps.append(ContinuousClock().measure { logbook.delete(todays[0]) })
        taps.append(ContinuousClock().measure { logbook.update(todays[1], time: .now, vessel: .pint, volumeMl: 568, price: 5) })

        let screens = try ContinuousClock().measure {
            let ledger = Ledger(days: try context.fetch(FetchDescriptor<Day>()), clock: clock)
            let goal = Goal(isEnabled: true, isDynamic: true, reductionPercent: 10, periodDays: 7)
            for offset in 0..<120 { _ = ledger.dailyBudget(on: today - offset, goal: goal) }
            for offset in 0..<28 { for back in 0..<7 { _ = ledger.dailyBudget(on: today - offset - back, goal: goal) } }
            for week in 0..<52 { _ = ledger.week(starting: clock.weekStart(of: today) - 7 * week, goal: goal) }
            _ = ledger.projection(goal: goal)
            _ = ledger.longestDryStreak(in: (today - 365)...today)
            let month = ledger.monthBefore(today)
            let pours = try context.fetch(Pour.on(month.lowerBound...today))
            _ = ledger.cumulative(pours, on: today)
            _ = ledger.averageCumulative(pours, over: month)
        }

        print("scale: setup \(setup), taps \(taps.map { $0.formatted(.units(allowed: [.milliseconds])) }), screens \(screens)")
        // The first touch after launch warms SwiftData's fetch machinery; after that a tap should be near-instant.
        #expect(taps[0] < .milliseconds(150))
        #expect(taps.dropFirst().allSatisfy { $0 < .milliseconds(30) })
        #expect(screens < .milliseconds(250))
    }
}
