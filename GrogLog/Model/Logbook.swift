import Foundation
import GRDB
import GRDBQuery
import WidgetKit
import os

/// Every change to the log goes through here, each as one transaction. After a change only the affected days'
/// totals are recomputed from their entries, so `Day` rows are always derived, never incremented, and cannot drift.
/// Observed queries refresh as each transaction commits.
nonisolated struct Logbook: Sendable {
    let writer: any DatabaseWriter
    let clock: DayClock
    /// Whether changed days are copied into Health afterwards. Off for demo data and tests so sample drinks are
    /// never written into the user's health record.
    var mirrorsToHealth = false

    // MARK: Entries

    func log(_ serve: Serve, at times: [Date]) {
        defer { mirror(Set(times.map { clock.day(for: $0) })) }
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
        defer { mirror([clock.day(for: time)]) }
        write { db in
            let drink = try unitsDrink(db)
            try Pour(drinkId: drink.id, timestamp: time, day: clock.day(for: time).number, vessel: .shot, volumeMl: units * 10, price: 0).insert(db)
            try retotal([clock.day(for: time)], db)
        }
    }

    func delete(_ pour: Pour) {
        defer { mirror([pour.dayKey]) }
        write { db in
            try pour.delete(db)
            try retotal([pour.dayKey], db)
        }
    }

    /// Removes the most recently logged drink on a day, by insertion order rather than timestamp, so undoing a
    /// backdated drink removes that one. The rowid gives insertion order; a pour's id is random and its timestamp
    /// is when it was drunk.
    func undo(on day: DayKey) {
        defer { mirror([day]) }
        write { db in
            guard let last = try Pour.filter(Column("day") == day.number).order(Column.rowID.desc).fetchOne(db) else { return }
            try last.delete(db)
            try retotal([day], db)
        }
    }

    func update(_ pour: Pour, time: Date, vessel: Vessel, volumeMl: Double, price: Double) {
        defer { mirror([pour.dayKey, clock.day(for: time)]) }
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

    /// Sets a day's spend manually, or clears it so spend is the sum of the drinks' prices.
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

    /// Saves a drink. If its strength or type changed, every day it was logged on is retotalled.
    func save(_ drink: Drink) {
        let touched = write { db -> Set<DayKey> in
            let before = try Drink.fetchOne(db, key: drink.id)
            try drink.save(db)
            guard let before, before.abv != drink.abv || before.category != drink.category else { return [] }
            let days = try Pour.select(Column("day"), as: Int.self).filter(Column("drinkId") == drink.id).distinct().fetchAll(db)
            let touched = Set(days.map(DayKey.init(number:)))
            try retotal(touched, db)
            return touched
        }
        mirror(touched ?? [])
    }

    /// Adds a new drink, pinned to the Log grid at its usual size.
    func add(_ drink: Drink) {
        write { db in
            try drink.insert(db)
            try Favourite(drinkId: drink.id, vessel: drink.vessel, volumeMl: drink.volumeMl, price: drink.price).insert(db)
        }
    }

    /// Only drinks never logged can be deleted (the schema refuses otherwise); the rest can be hidden.
    func delete(_ drink: Drink) {
        write { db in _ = try drink.delete(db) }
    }

    /// The drink with this name and type, or a new one created at this size.
    func drink(named name: String, category: DrinkCategory, abv: Double, vessel: Vessel, volumeMl: Double, price: Double = 0) -> Drink? {
        write { db in try findOrCreate(name: name, category: category, abv: abv, vessel: vessel, volumeMl: volumeMl, price: price, db) }
    }

    func pin(_ serve: Serve) {
        write { db in try Favourite(drinkId: serve.drink.id, vessel: serve.vessel, volumeMl: serve.volumeMl, price: serve.price).insert(db) }
    }

    func unpin(_ favourite: Favourite) {
        write { db in _ = try favourite.delete(db) }
    }

    /// Resets every drink and Log tile to the catalogue price, for prices that drifted or were never set. Drinks
    /// the catalogue does not price are left alone, and logged entries keep the price recorded at the time.
    /// Returns how many changed.
    @discardableResult
    func resetPrices() -> Int {
        write { db in
            var changed = 0
            for var drink in try Drink.fetchAll(db) {
                guard let price = Catalog.price(name: drink.name, category: drink.category, vessel: drink.vessel, ml: drink.volumeMl),
                      price != drink.price else { continue }
                drink.price = price
                try drink.update(db)
                changed += 1
            }
            for var favourite in try Favourite.fetchAll(db) {
                guard let drink = try Drink.fetchOne(db, key: favourite.drinkId),
                      let price = Catalog.price(name: drink.name, category: drink.category, vessel: favourite.vessel, ml: favourite.volumeMl),
                      price != favourite.price else { continue }
                favourite.price = price
                try favourite.update(db)
                changed += 1
            }
            return changed
        } ?? 0
    }

    // MARK: Rebuilding

    /// Recomputes every day in one transaction, after an import or when the day-end hour changes (which moves
    /// entries between days).
    func rebuild(reassigningDays: Bool = false) {
        defer { if mirrorsToHealth { Task { await Health.shared.mirrorEverything(self) } } }
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
            let totals = Dictionary(grouping: try entries(in: nil, db), by: \.day).mapValues { DayTotals($0) }
            // Rewritten in place: deleting and reinserting days would fire the sync triggers for every dry mark
            // and manual spend, resending them all from every device.
            for var row in try Day.fetchAll(db) {
                row.set(totals[row.number] ?? DayTotals())
                if row.count == 0 && !row.isAlcoholFree && row.costOverride == nil {
                    try row.delete(db)
                } else {
                    try row.update(db)
                }
            }
            for (number, dayTotals) in totals where try !Day.exists(db, key: number) {
                try Day(number: number, totals: dayTotals).insert(db)
            }
        }
    }

    /// Runs a batch of writes, such as an import, as one transaction, retotalling the touched days at the end.
    func bulk(_ body: (Database) throws -> Set<DayKey>) throws {
        let touched = try writer.write { db in
            let days = try body(db)
            try retotal(days, db)
            return days
        }
        mirror(touched)
    }

    // MARK: Internals

    /// Recomputes days from their entries. Logging a drink clears a dry mark; a day left with neither is deleted.
    func retotal(_ days: Set<DayKey>, _ db: Database) throws {
        for day in days {
            var row = try Day.fetchOne(db, key: day.number) ?? Day(number: day.number)
            let entries = try entries(in: day...day, db)
            row.set(DayTotals(entries))
            if !entries.isEmpty { row.isAlcoholFree = false }
            try save(row, db)
        }
    }

    func findOrCreate(name: String, category: DrinkCategory, abv: Double, vessel: Vessel, volumeMl: Double, price: Double = 0, _ db: Database) throws -> Drink {
        if let drink = try Drink.filter(Column("name") == name && Column("category") == category.rawValue).fetchOne(db) { return drink }
        let drink = Drink(name: name, category: category, abv: abv, vessel: vessel, volumeMl: volumeMl, price: price)
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

    /// Mirrors changed days to Health after the transaction, never inside it, so the log never waits on Health or
    /// fails with it.
    private func mirror(_ days: Set<DayKey>) {
        guard mirrorsToHealth, !days.isEmpty else { return }
        Task { await Health.shared.mirror(days, self) }
    }

    @discardableResult
    private func write<T>(_ body: (Database) throws -> T) -> T? {
        do {
            let result = try writer.write(body)
            // Widgets run in a separate process and are not notified of writes to the shared file.
            WidgetCenter.shared.reloadAllTimelines()
            return result
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
        Logbook(writer: try! writer, clock: prefs.clock, mirrorsToHealth: prefs.mirrorsToHealth)
    }
}
