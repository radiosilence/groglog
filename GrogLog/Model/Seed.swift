import Foundation
import GRDB
import GrogLogCore

nonisolated enum Seed {
    /// Generic drinks at Drinkaware's standard strengths, with the sizes that start out on the Log grid, from the
    /// shared core.
    private static let generics: [(name: String, category: DrinkCategory, serves: [(Vessel, Double, Double)])] = catalogGenerics().compactMap { record in
        guard let category = DrinkCategory(rawValue: record.category) else { return nil }
        return (record.name, category, record.serves.compactMap { serve in Vessel(rawValue: serve.vessel).map { ($0, serve.ml, serve.price) } })
    }

    /// A generic serve's starting price, for repairing databases seeded before generics carried prices.
    static func price(name: String, vessel: Vessel, ml: Double) -> Double? {
        catalogGenericPrice(name: name, vessel: vessel.rawValue, ml: ml)
    }

    /// Generic drinks and their starting Log-grid tiles, on a fresh install.
    static func drinksIfNeeded(_ logbook: Logbook) throws {
        // Every process start comes here, widget refreshes included; a read does not take the write lock the
        // other process may want.
        guard try logbook.writer.read({ try Drink.fetchCount($0) }) == 0 else { return }
        try logbook.writer.write { db in
            guard try Drink.fetchCount(db) == 0 else { return }
            // Tiles are marked for sync, which keeps them back until it knows whether iCloud already holds a grid.
            func tile(_ favourite: Favourite) throws {
                try favourite.insert(db)
                try db.execute(sql: "INSERT INTO syncSeeded (recordName) SELECT 'favourite-' || hex(id) FROM favourite WHERE id = ?", arguments: [favourite.id])
            }
            let units = try logbook.unitsDrink(db)
            try tile(Favourite(drinkId: units.id, vessel: .shot, volumeMl: 10, price: 0, sortOrder: 99))
            var order = 100
            for generic in generics {
                let (vessel, ml, price) = generic.serves[0]
                let drink = Drink(name: generic.name, category: generic.category, abv: generic.category.defaultABV, vessel: vessel, volumeMl: ml, price: price, isGeneric: true, sortOrder: order)
                try drink.insert(db)
                for (vessel, ml, price) in generic.serves {
                    try tile(Favourite(drinkId: drink.id, vessel: vessel, volumeMl: ml, price: price, sortOrder: order))
                    order += 1
                }
            }
        }
    }

    #if DEBUG
    /// Sample history for demo mode's in-memory database. The current month shows a heavy first week, a failed dry
    /// spell, a binge starting at 5am on wine, then a taper of beers starting later each evening. Earlier months
    /// show a steady baseline.
    static func sample(_ logbook: Logbook, days: Int = 120) throws {
        let clock = logbook.clock
        let today = clock.today
        let thisMonth = today.monthStart
        let dryRun = 6...11
        let binge = 12...13
        let taperFrom = 14
        var rng = SeededRandom(seed: 42)

        try logbook.bulk { db in
            let beers = try [
                favourite("Stella Artois", .beer, 4.6, .can, 440, 1.75, logbook, db),
                favourite("Gipsy Hill Hepcat", .beer, 4.6, .pint, 568, 6.50, logbook, db),
            ]
            let heavy = try beers + [
                favourite("Henry Westons Vintage", .cider, 8.2, .bottle, 500, 2.75, logbook, db),
            ]
            let wine = try favourite("Rioja", .redWine, 13.5, .wineGlass, 250, 6.50, logbook, db)

            var touched: Set<DayKey> = []
            for offset in (1...days).reversed() {
                let day = clock.today - offset
                let date = day.components.day
                let thisMonth = day.monthStart == thisMonth
                let onTheWine = thisMonth && binge.contains(date)
                // How far into the taper, once it starts.
                let taper = thisMonth && date >= taperFrom
                    ? min(1, Double(date - taperFrom) / Double(max(1, today.components.day - taperFrom)))
                    : 0

                // Yesterday is always an evening out, so a screenshot of it has a day to show.
                let yesterday = offset == 1
                if thisMonth && dryRun.contains(date) && !yesterday {
                    try Day(number: day.number, isAlcoholFree: true).save(db)
                    continue
                }
                if !onTheWine, Double.random(in: 0..<1, using: &rng) < (taper > 0 ? 0.1 + taper * 0.3 : 0.08), !yesterday {
                    try Day(number: day.number, isAlcoholFree: true).save(db)
                    continue
                }
                if !thisMonth, Double.random(in: 0..<1, using: &rng) < 0.05, !yesterday { continue }

                // The taper sets the level; the noise is small.
                let target = onTheWine
                    ? Double.random(in: 42...48, using: &rng)
                    : taper > 0
                        ? (30 - taper * 22) * Double.random(in: 0.9...1.1, using: &rng)
                        : Double.random(in: 28...38, using: &rng)
                // The binge starts at first light; on the taper the first drink creeps later each evening.
                let opening = onTheWine
                    ? Double.random(in: 0.2...1, using: &rng)
                    : Double.random(in: 8...10, using: &rng) + taper * 5
                var time = clock.start(of: day).addingTimeInterval(opening * 3600)
                var total = 0.0
                while total < target {
                    let serve = onTheWine && Int.random(in: 0..<10, using: &rng) < 7 ? wine
                        : (taper > 0 ? beers : heavy).randomElement(using: &rng)!
                    try Pour(drinkId: serve.drink.id, timestamp: time, day: day.number, vessel: serve.vessel, volumeMl: serve.volumeMl, price: serve.price).insert(db)
                    total += serve.units
                    time = time.addingTimeInterval(Double.random(in: onTheWine ? 20...30 : taper > 0 ? 35...65 : 25...45, using: &rng) * 60)
                }
                touched.insert(day)
            }
            return touched
        }
    }

    /// Sample watch readings that respond to the log: a heavy night lowers the next morning's HRV and raises resting
    /// rate, and a run of them shifts the baseline, so a dry week shows as recovery. Includes a gap of a few weeks
    /// where the watch stopped syncing with Health.
    static func nights(_ ledger: Ledger, days: Int = 150) -> Nights {
        var rng = SeededRandom(seed: 7)
        let today = ledger.today
        let units = { (day: DayKey) in ledger.totals(on: day).units }
        var byDay: [DayKey: Night] = [:]
        for day in (today - days)..<today {
            // Occasional nights off the wrist.
            if Double.random(in: 0..<1, using: &rng) < 0.06 || ((today - 75)...(today - 40)).contains(day) { continue }
            let week = ((day - 6)...day).map(units).reduce(0, +) / 7
            byDay[day] = Night(
                hrv: 64 - units(day) * 0.45 - week * 0.35 + Double.random(in: -4...4, using: &rng),
                restingHR: 51 + units(day) * 0.12 + week * 0.22 + Double.random(in: -1.5...1.5, using: &rng),
                sleepingHR: 48 + units(day) * 0.35 + week * 0.1 + Double.random(in: -1.5...1.5, using: &rng),
                // Drinking shortens the night slightly, mostly at the expense of REM.
                sleep: Sleep(
                    deep: (1.4 - units(day) * 0.01 + Double.random(in: -0.2...0.2, using: &rng)) * 3600,
                    core: (4 - units(day) * 0.01 + Double.random(in: -0.4...0.4, using: &rng)) * 3600,
                    rem: max(0.2, 1.8 - units(day) * 0.04 + Double.random(in: -0.2...0.2, using: &rng)) * 3600,
                    awake: (0.3 + units(day) * 0.02 + Double.random(in: 0...0.2, using: &rng)) * 3600
                )
            )
        }
        return Nights(byDay: byDay)
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

#if DEBUG
nonisolated struct SeededRandom: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return seed
    }
}
#endif
