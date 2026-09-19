import Foundation
import SwiftData

enum Seed {
    static func drinksIfNeeded(_ context: ModelContext) {
        _ = context.unitsDrink()
        guard (try? context.fetchCount(FetchDescriptor<Drink>())) == 1 else { return }
        let generics: [Drink] = [
            Drink(name: "Pint of beer", category: .beer, vessel: .pint, volumeMl: 568, abv: 4.5, price: 5.50, isGeneric: true),
            Drink(name: "Half of beer", category: .beer, vessel: .half, volumeMl: 284, abv: 4.5, price: 3.00, isGeneric: true),
            Drink(name: "Can of beer", category: .beer, vessel: .can, volumeMl: 440, abv: 4.5, price: 2.00, isGeneric: true),
            Drink(name: "Can of beer", category: .beer, vessel: .can, volumeMl: 500, abv: 5.0, price: 2.50, isGeneric: true),
            Drink(name: "Bottle of beer", category: .beer, vessel: .bottle, volumeMl: 330, abv: 5.0, price: 4.50, isGeneric: true),
            Drink(name: "Bottle of beer", category: .beer, vessel: .bottle, volumeMl: 660, abv: 5.0, price: 7.00, isGeneric: true),
            Drink(name: "Pint of stout", category: .stout, vessel: .pint, volumeMl: 568, abv: 4.2, price: 5.80, isGeneric: true),
            Drink(name: "Pint of cider", category: .cider, vessel: .pint, volumeMl: 568, abv: 4.5, price: 5.50, isGeneric: true),
            Drink(name: "Bottle of cider", category: .cider, vessel: .bottle, volumeMl: 500, abv: 4.5, price: 3.00, isGeneric: true),
            Drink(name: "Glass of red", category: .redWine, vessel: .wineGlass, volumeMl: 175, abv: 13.5, price: 6.50, isGeneric: true),
            Drink(name: "Large red", category: .redWine, vessel: .wineGlass, volumeMl: 250, abv: 13.5, price: 8.50, isGeneric: true),
            Drink(name: "Glass of white", category: .whiteWine, vessel: .wineGlass, volumeMl: 175, abv: 12.5, price: 6.50, isGeneric: true),
            Drink(name: "Small white", category: .whiteWine, vessel: .wineGlass, volumeMl: 125, abv: 12.5, price: 5.00, isGeneric: true),
            Drink(name: "Glass of rosé", category: .rose, vessel: .wineGlass, volumeMl: 175, abv: 12, price: 6.50, isGeneric: true),
            Drink(name: "Bottle of wine", category: .redWine, vessel: .wineBottle, volumeMl: 750, abv: 13.5, price: 9.00, isGeneric: true),
            Drink(name: "Glass of fizz", category: .bubbles, vessel: .flute, volumeMl: 125, abv: 11, price: 7.00, isGeneric: true),
            Drink(name: "Bottle of fizz", category: .bubbles, vessel: .wineBottle, volumeMl: 750, abv: 11, price: 12.00, isGeneric: true),
            Drink(name: "Single spirit", category: .spirit, vessel: .shot, volumeMl: 25, abv: 40, price: 4.00, isGeneric: true),
            Drink(name: "Double spirit", category: .spirit, vessel: .tumbler, volumeMl: 50, abv: 40, price: 7.00, isGeneric: true),
            Drink(name: "Alcopop", category: .alcopop, vessel: .bottle, volumeMl: 275, abv: 4, price: 3.50, isGeneric: true),
            Drink(name: "Cocktail", category: .cocktail, vessel: .coupe, volumeMl: 150, abv: 15, price: 10.00, isGeneric: true),
            Drink(name: "Port or sherry", category: .fortified, vessel: .wineGlass, volumeMl: 50, abv: 20, price: 4.00, isGeneric: true),
        ]
        for (index, drink) in generics.enumerated() {
            drink.order = 100 + index
            context.insert(drink)
        }
    }

    #if DEBUG
    /// Three months of history shaped like the original Drink Coach screenshots: mostly heavy days, the odd dry run,
    /// a few gaps, and the real 12–18 Sep 2026 totals. Days that already have drinks are left alone.
    static func sample(_ context: ModelContext, prefs: Prefs) {
        let clock = prefs.clock
        let today = clock.today
        let existing = Set(((try? context.fetch(FetchDescriptor<Pour>())) ?? []).map { clock.day(for: $0.timestamp) })
        let favourites = [
            favourite(named: "Stella Artois", .beer, .can, 440, 4.6, 1.75, in: context),
            favourite(named: "Henry Westons Vintage", .cider, .bottle, 500, 8.2, 2.75, in: context),
            favourite(named: "Gipsy Hill Hepcat", .beer, .pint, 568, 4.6, 6.50, in: context),
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
                let drink = favourites[Int.random(in: 0..<10, using: &rng) < 6 ? 0 : Int.random(in: 1...2, using: &rng)]
                context.insert(Pour(drink: drink, at: time))
                units += drink.units
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

    private static func favourite(named name: String, _ category: DrinkCategory, _ vessel: Vessel, _ ml: Double, _ abv: Double, _ price: Double, in context: ModelContext) -> Drink {
        if let drink = try? context.fetch(FetchDescriptor(predicate: #Predicate<Drink> { $0.name == name })).first { return drink }
        let drink = Drink(name: name, category: category, vessel: vessel, volumeMl: ml, abv: abv, price: price, isFavourite: true)
        context.insert(drink)
        return drink
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
