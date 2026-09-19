import Foundation
import SwiftData

enum Seed {
    /// Generic drinks at Drinkaware's standard strengths, with the sizes that start out on the Log grid.
    private static let generics: [(name: String, category: DrinkCategory, serves: [(Vessel, Double, Double)])] = [
        ("Beer", .beer, [(.pint, 568, 5.50), (.half, 284, 3.00), (.can, 440, 2.00), (.can, 500, 2.50), (.bottle, 330, 4.50), (.bottle, 660, 7.00)]),
        ("Stout", .stout, [(.pint, 568, 5.80)]),
        ("Cider", .cider, [(.pint, 568, 5.50), (.bottle, 500, 3.00)]),
        ("Red wine", .redWine, [(.wineGlass, 175, 6.50), (.wineGlass, 250, 8.50), (.wineBottle, 750, 9.00)]),
        ("White wine", .whiteWine, [(.wineGlass, 175, 6.50), (.wineGlass, 125, 5.00)]),
        ("Rosé", .rose, [(.wineGlass, 175, 6.50)]),
        ("Fizz", .bubbles, [(.flute, 125, 7.00), (.wineBottle, 750, 12.00)]),
        ("Spirits", .spirit, [(.shot, 25, 4.00)]),
        ("Alcopop", .alcopop, [(.bottle, 275, 3.50)]),
        ("Cocktail", .cocktail, [(.coupe, 150, 10.00)]),
        ("Port or sherry", .fortified, [(.wineGlass, 50, 4.00)]),
    ]

    static func drinksIfNeeded(_ context: ModelContext) {
        let units = context.unitsDrink()
        guard (try? context.fetchCount(FetchDescriptor<Drink>())) == 1 else { return }
        context.insert(Favourite(drink: units, vessel: .shot, volumeMl: 10, price: 0, order: 99))
        var order = 100
        for generic in generics {
            let (vessel, ml, price) = generic.serves[0]
            let drink = Drink(name: generic.name, category: generic.category, abv: generic.category.defaultABV, vessel: vessel, volumeMl: ml, price: price, isGeneric: true, order: order)
            context.insert(drink)
            for (vessel, ml, price) in generic.serves {
                context.insert(Favourite(drink: drink, vessel: vessel, volumeMl: ml, price: price, order: order))
                order += 1
            }
        }
        try? context.save()
    }

    #if DEBUG
    /// Three months of history shaped like the original Drink Coach screenshots: mostly heavy days, the odd dry run,
    /// a few gaps, and the real 12–18 Sep 2026 totals. Days that already have drinks are left alone.
    static func sample(_ context: ModelContext, prefs: Prefs) {
        let clock = prefs.clock
        let today = clock.today
        let existing = Set(((try? context.fetch(FetchDescriptor<Pour>())) ?? []).map { clock.day(for: $0.timestamp) })
        let favourites = [
            favourite(named: "Stella Artois", .beer, 4.6, .can, 440, 1.75, in: context),
            favourite(named: "Henry Westons Vintage", .cider, 8.2, .bottle, 500, 2.75, in: context),
            favourite(named: "Gipsy Hill Hepcat", .beer, 4.6, .pint, 568, 6.50, in: context),
        ]
        let screenshot: [String: (units: Double, kcal: Double, cost: Double)] = [
            "2026-09-12": (30.6, 2696, 42.00), "2026-09-13": (27.6, 2328, 34.80), "2026-09-14": (40.5, 3160, 49.70),
            "2026-09-15": (35.5, 2278, 36.60), "2026-09-16": (38.8, 3236, 48.60), "2026-09-17": (29.2, 2611, 36.50),
            "2026-09-18": (29.1, 2444, 32.80),
        ]
        let dryRun = Set((6...11).map { String(format: "2026-09-%02d", $0) })

        var rng = SeededRandom(seed: 42)
        for offset in (1...90).reversed() {
            let day = clock.adding(-offset, to: today)
            let key = clock.key(day)
            guard !existing.contains(day) else { continue }
            if dryRun.contains(key) {
                context.setAlcoholFree(true, on: day)
                continue
            }
            let evening = clock.calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day)!
            if let total = screenshot[key] {
                context.insert(Pour(drink: context.unitsDrink(), at: evening, volumeMl: total.units * 10, price: total.cost, kcalOverride: total.kcal))
                continue
            }
            let roll = Double.random(in: 0..<1, using: &rng)
            if roll < 0.06 { continue }
            if roll < 0.14 {
                context.setAlcoholFree(true, on: day)
                continue
            }
            let weekend = [1, 6, 7].contains(clock.calendar.component(.weekday, from: day))
            let target = Double.random(in: weekend ? 28...42 : 18...34, using: &rng)
            var time = clock.calendar.date(bySettingHour: 13, minute: Int.random(in: 0..<59, using: &rng), second: 0, of: day)!
            var units = 0.0
            while units < target {
                let serve = favourites[Int.random(in: 0..<10, using: &rng) < 6 ? 0 : Int.random(in: 1...2, using: &rng)]
                context.insert(Pour(serve, at: time))
                units += serve.units
                time = time.addingTimeInterval(Double.random(in: 20...40, using: &rng) * 60)
            }
        }
        if !prefs.goal.isEnabled {
            prefs.goal = Goal(isEnabled: true, isDynamic: true, reductionPercent: 10, periodDays: 1)
        }
    }

    static func eraseHistory(_ context: ModelContext) {
        try? context.delete(model: Pour.self)
        try? context.delete(model: AlcoholFreeDay.self)
    }

    private static func favourite(named name: String, _ category: DrinkCategory, _ abv: Double, _ vessel: Vessel, _ ml: Double, _ price: Double, in context: ModelContext) -> Serve {
        let drink = context.drink(named: name, category: category, abv: abv, vessel: vessel, volumeMl: ml)
        drink.price = price
        let serve = Serve(drink, vessel, ml, price: price)
        if !(drink.favourites ?? []).contains(where: { $0.vessel == vessel && $0.volumeMl == ml }) {
            context.insert(Favourite(drink: drink, vessel: vessel, volumeMl: ml, price: price))
        }
        return serve
    }
    #endif
}

struct SeededRandom: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return seed
    }
}
