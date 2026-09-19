import Foundation
import GRDB

nonisolated enum Seed {
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

    /// Generic drinks and their starting Log-grid tiles, on a fresh install.
    static func drinksIfNeeded(_ logbook: Logbook) throws {
        try logbook.writer.write { db in
            guard try Drink.fetchCount(db) == 0 else { return }
            let units = try logbook.unitsDrink(db)
            try Favourite(drinkId: units.id, vessel: .shot, volumeMl: 10, price: 0, sortOrder: 99).insert(db)
            var order = 100
            for generic in generics {
                let (vessel, ml, price) = generic.serves[0]
                let drink = Drink(name: generic.name, category: generic.category, abv: generic.category.defaultABV, vessel: vessel, volumeMl: ml, price: price, isGeneric: true, sortOrder: order)
                try drink.insert(db)
                for (vessel, ml, price) in generic.serves {
                    try Favourite(drinkId: drink.id, vessel: vessel, volumeMl: ml, price: price, sortOrder: order).insert(db)
                    order += 1
                }
            }
        }
    }

    #if DEBUG
    /// History shaped like the original Drink Coach screenshots — mostly heavy days, the odd dry run, a few gaps, and
    /// the real 12–18 Sep 2026 totals — over `days` days, in one transaction. For demo mode's own in-memory database.
    static func sample(_ logbook: Logbook, days: Int = 120) throws {
        let clock = logbook.clock
        let screenshot: [String: (units: Double, kcal: Double, cost: Double)] = [
            "2026-09-12": (30.6, 2696, 42.00), "2026-09-13": (27.6, 2328, 34.80), "2026-09-14": (40.5, 3160, 49.70),
            "2026-09-15": (35.5, 2278, 36.60), "2026-09-16": (38.8, 3236, 48.60), "2026-09-17": (29.2, 2611, 36.50),
            "2026-09-18": (29.1, 2444, 32.80),
        ]
        let dryRun = Set((6...11).map { String(format: "2026-09-%02d", $0) })
        var rng = SeededRandom(seed: 42)

        try logbook.bulk { db in
            let favourites = try [
                favourite("Stella Artois", .beer, 4.6, .can, 440, 1.75, logbook, db),
                favourite("Henry Westons Vintage", .cider, 8.2, .bottle, 500, 2.75, logbook, db),
                favourite("Gipsy Hill Hepcat", .beer, 4.6, .pint, 568, 6.50, logbook, db),
            ]
            let units = try logbook.unitsDrink(db)
            var touched: Set<DayKey> = []
            for offset in (1...days).reversed() {
                let day = clock.today - offset
                if dryRun.contains(day.description) {
                    try Day(number: day.number, isAlcoholFree: true).save(db)
                    continue
                }
                if let total = screenshot[day.description] {
                    let evening = clock.start(of: day).addingTimeInterval(14 * 3600)
                    try Pour(drinkId: units.id, timestamp: evening, day: day.number, vessel: .shot, volumeMl: total.units * 10, price: total.cost, kcalOverride: total.kcal).insert(db)
                    touched.insert(day)
                    continue
                }
                let roll = Double.random(in: 0..<1, using: &rng)
                if roll < 0.06 { continue }
                if roll < 0.14 {
                    try Day(number: day.number, isAlcoholFree: true).save(db)
                    continue
                }
                let target = Double.random(in: [1, 6, 7].contains(day.weekday) ? 28...42 : 18...34, using: &rng)
                var time = clock.start(of: day).addingTimeInterval(Double.random(in: 8...9, using: &rng) * 3600)
                var total = 0.0
                while total < target {
                    let serve = favourites[Int.random(in: 0..<10, using: &rng) < 6 ? 0 : Int.random(in: 1...2, using: &rng)]
                    try Pour(drinkId: serve.drink.id, timestamp: time, day: day.number, vessel: serve.vessel, volumeMl: serve.volumeMl, price: serve.price).insert(db)
                    total += serve.units
                    time = time.addingTimeInterval(Double.random(in: 20...40, using: &rng) * 60)
                }
                touched.insert(day)
            }
            return touched
        }
    }

    private static func favourite(_ name: String, _ category: DrinkCategory, _ abv: Double, _ vessel: Vessel, _ ml: Double, _ price: Double, _ logbook: Logbook, _ db: Database) throws -> Serve {
        var drink = try logbook.findOrCreate(name: name, category: category, abv: abv, vessel: vessel, volumeMl: ml, db)
        drink.price = price
        try drink.update(db)
        if try Favourite.filter(Column("drinkId") == drink.id && Column("vessel") == vessel.rawValue && Column("volumeMl") == ml).fetchCount(db) == 0 {
            try Favourite(drinkId: drink.id, vessel: vessel, volumeMl: ml, price: price).insert(db)
        }
        return Serve(drink, vessel, ml, price: price)
    }
    #endif
}

nonisolated struct SeededRandom: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return seed
    }
}
