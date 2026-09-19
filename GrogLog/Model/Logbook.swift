import Foundation
import GRDB
import GRDBQuery
import os

/// Every change to the log goes through here, each as one transaction. After a change the affected days' totals are
/// recomputed from their entries — only those days, however long the history — so `Day` rows are always derived,
/// never incremented, and can't drift. Observed queries refresh as each transaction commits.
nonisolated struct Logbook: Sendable {
    let writer: any DatabaseWriter
    let clock: DayClock

    // MARK: Entries

    func log(_ serve: Serve, at times: [Date]) {
        write { db in
            for time in times {
                try Pour(drinkId: serve.drink.id, timestamp: time, day: clock.day(for: time).number, vessel: serve.vessel, volumeMl: serve.volumeMl, price: serve.price).insert(db)
            }
            if let latest = times.max() {
                try Favourite
                    .filter(Column("drinkId") == serve.drink.id && Column("vessel") == serve.vessel.rawValue && Column("volumeMl") == serve.volumeMl)
                    .updateAll(db, Column("lastUsed").set(to: latest))
            }
            try retotal(Set(times.map { clock.day(for: $0) }), db)
        }
    }

    func logUnits(_ units: Double, at time: Date) {
        write { db in
            let drink = try unitsDrink(db)
            try Pour(drinkId: drink.id, timestamp: time, day: clock.day(for: time).number, vessel: .shot, volumeMl: units * 10, price: 0).insert(db)
            try retotal([clock.day(for: time)], db)
        }
    }

    func delete(_ pour: Pour) {
        write { db in
            try pour.delete(db)
            try retotal([pour.dayKey], db)
        }
    }

    func update(_ pour: Pour, time: Date, vessel: Vessel, volumeMl: Double, price: Double) {
        write { db in
            var updated = pour
            updated.timestamp = time
            updated.day = clock.day(for: time).number
            updated.vessel = vessel
            updated.volumeMl = volumeMl
            updated.price = price
            try updated.update(db)
            try retotal([pour.dayKey, updated.dayKey], db)
        }
    }

    /// Sets a day's spend by hand, or clears it back to what the drinks add up to.
    func setSpend(_ amount: Double?, on day: DayKey) {
        write { db in
            var row = try Day.fetchOne(db, key: day.number) ?? Day(number: day.number)
            row.costOverride = amount
            try save(row, db)
        }
    }

    func setAlcoholFree(_ dry: Bool, on day: DayKey) {
        write { db in
            var row = try Day.fetchOne(db, key: day.number) ?? Day(number: day.number)
            row.isAlcoholFree = dry
            try save(row, db)
        }
    }

    // MARK: Drinks

    /// Saves a drink. If its strength or type changed, every day it was had on is re-totted.
    func save(_ drink: Drink) {
        write { db in
            let before = try Drink.fetchOne(db, key: drink.id)
            try drink.save(db)
            if let before, before.abv != drink.abv || before.category != drink.category {
                let days = try Pour.select(Column("day"), as: Int.self).filter(Column("drinkId") == drink.id).distinct().fetchAll(db)
                try retotal(Set(days.map(DayKey.init(number:))), db)
            }
        }
    }

    /// Adds a new drink, pinned to the Log grid at its usual size.
    func add(_ drink: Drink) {
        write { db in
            try drink.insert(db)
            try Favourite(drinkId: drink.id, vessel: drink.vessel, volumeMl: drink.volumeMl, price: drink.price).insert(db)
        }
    }

    /// Only drinks never logged can go (the schema refuses otherwise); the rest can be hidden.
    func delete(_ drink: Drink) {
        write { db in _ = try drink.delete(db) }
    }

    /// The drink with this name and type, or a new one first had at this size.
    func drink(named name: String, category: DrinkCategory, abv: Double, vessel: Vessel, volumeMl: Double) -> Drink? {
        write { db in try findOrCreate(name: name, category: category, abv: abv, vessel: vessel, volumeMl: volumeMl, db) }
    }

    func pin(_ serve: Serve) {
        write { db in try Favourite(drinkId: serve.drink.id, vessel: serve.vessel, volumeMl: serve.volumeMl, price: serve.price).insert(db) }
    }

    func unpin(_ favourite: Favourite) {
        write { db in _ = try favourite.delete(db) }
    }

    // MARK: Rebuilding

    /// Recomputes every day from scratch — after an import, or when the hour days end at changes (which moves
    /// entries between days). The same arithmetic as for a single change, over everything, in one transaction.
    func rebuild(reassigningDays: Bool = false) {
        write { db in
            if reassigningDays {
                for var pour in try Pour.fetchAll(db) {
                    let day = clock.day(for: pour.timestamp).number
                    if day != pour.day {
                        pour.day = day
                        try pour.update(db)
                    }
                }
            }
            let dry = try Day.select(Column("number"), as: Int.self).filter(Column("isAlcoholFree")).fetchAll(db)
            // Marks and hand-set spends aren't derived from entries, so they're carried across the rebuild.
            let spends = try Day.filter(Column("costOverride") != nil).fetchAll(db).reduce(into: [Int: Double]()) { $0[$1.number] = $1.costOverride }
            try Day.deleteAll(db)
            for (number, entries) in Dictionary(grouping: try entries(in: nil, db), by: \.day) {
                var row = Day(number: number, totals: DayTotals(entries))
                row.costOverride = spends[number]
                try row.insert(db)
            }
            for number in dry where try !Day.exists(db, key: number) {
                try Day(number: number, isAlcoholFree: true, costOverride: spends[number]).insert(db)
            }
            for (number, amount) in spends where try !Day.exists(db, key: number) {
                try Day(number: number, costOverride: amount).insert(db)
            }
        }
    }

    /// Runs a batch of writes — an import — as one transaction, re-totting the days it touched at the end.
    func bulk(_ body: (Database) throws -> Set<DayKey>) throws {
        try writer.write { db in
            try retotal(try body(db), db)
        }
    }

    // MARK: Internals

    /// Recomputes days from their entries. Logging a drink clears a dry mark; a day left with neither goes.
    func retotal(_ days: Set<DayKey>, _ db: Database) throws {
        for day in days {
            var row = try Day.fetchOne(db, key: day.number) ?? Day(number: day.number)
            let entries = try entries(in: day...day, db)
            row.set(DayTotals(entries))
            if !entries.isEmpty { row.isAlcoholFree = false }
            try save(row, db)
        }
    }

    func findOrCreate(name: String, category: DrinkCategory, abv: Double, vessel: Vessel, volumeMl: Double, _ db: Database) throws -> Drink {
        if let drink = try Drink.filter(Column("name") == name && Column("category") == category.rawValue).fetchOne(db) { return drink }
        let drink = Drink(name: name, category: category, abv: abv, vessel: vessel, volumeMl: volumeMl)
        try drink.insert(db)
        return drink
    }

    func unitsDrink(_ db: Database) throws -> Drink {
        if let drink = try Drink.filter(Column("category") == DrinkCategory.units.rawValue).fetchOne(db) { return drink }
        let drink = Drink(name: "Units", category: .units, abv: 100, vessel: .shot, volumeMl: 10, isGeneric: true, sortOrder: 99)
        try drink.insert(db)
        return drink
    }

    private func entries(in days: ClosedRange<DayKey>?, _ db: Database) throws -> [Entry] {
        var request = Pour.including(required: Pour.drink)
        if let days { request = request.filter((days.lowerBound.number...days.upperBound.number).contains(Column("day"))) }
        return try request.asRequest(of: Entry.self).fetchAll(db)
    }

    private func save(_ row: Day, _ db: Database) throws {
        if row.count == 0 && !row.isAlcoholFree && row.costOverride == nil {
            _ = try row.delete(db)
        } else {
            try row.save(db)
        }
    }

    @discardableResult
    private func write<T>(_ body: (Database) throws -> T) -> T? {
        do {
            return try writer.write(body)
        } catch {
            Logger(subsystem: "cc.blit.groglog", category: "logbook").fault("Write failed: \(error)")
            assertionFailure("Write failed: \(error)")
            return nil
        }
    }
}

nonisolated extension Day {
    init(number: Int, totals: DayTotals) {
        self.init(number: number)
        set(totals)
    }

    mutating func set(_ totals: DayTotals) {
        units = totals.units
        kcal = totals.kcal
        cost = totals.cost
        count = totals.count
    }
}

extension DatabaseContext {
    /// Writes for views, which find the database in the environment.
    func logbook(_ prefs: Prefs) -> Logbook {
        Logbook(writer: try! writer, clock: prefs.clock)
    }
}
