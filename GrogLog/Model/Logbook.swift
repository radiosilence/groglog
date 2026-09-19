import Foundation
import SwiftData

/// Every change to what's been drunk goes through here. After each change the affected days' totals are recomputed
/// from their entries — only those days, however long the history — so `Day` rows are always derived, never
/// incremented, and can't drift.
struct Logbook {
    let context: ModelContext
    let clock: DayClock

    func log(_ serve: Serve, at times: [Date]) {
        for time in times {
            context.insert(Pour(drink: serve.drink, at: time, day: clock.day(for: time), vessel: serve.vessel, volumeMl: serve.volumeMl, price: serve.price))
        }
        if let latest = times.max() {
            favourite(for: serve)?.lastUsed = latest
        }
        refresh(Set(times.map(clock.day(for:))))
    }

    func logUnits(_ units: Double, at time: Date) {
        log(Serve(context.unitsDrink(), .shot, units * 10, price: 0), at: [time])
    }

    func delete(_ pour: Pour) {
        let day = pour.dayKey
        context.delete(pour)
        refresh([day])
    }

    func update(_ pour: Pour, time: Date, vessel: Vessel, volumeMl: Double, price: Double) {
        let before = pour.dayKey
        pour.timestamp = time
        pour.day = clock.day(for: time).number
        pour.vesselRaw = vessel.rawValue
        pour.volumeMl = volumeMl
        pour.price = price
        refresh([before, pour.dayKey])
    }

    func setAlcoholFree(_ dry: Bool, on day: DayKey) {
        guard let row = row(for: day, creating: dry) else { return }
        row.isAlcoholFree = dry
        tidy(row)
    }

    /// A drink's strength or type changed, so every day it was had on needs re-totting.
    func drinkChanged(_ drink: Drink) {
        refresh(Set((drink.pours ?? []).map(\.dayKey)))
    }

    /// Recomputes days from their entries. Logging a drink clears a dry mark; a day left with neither goes.
    func refresh(_ days: Set<DayKey>) {
        for day in days {
            let pours = (try? context.fetch(Pour.on(day...day))) ?? []
            guard let row = row(for: day, creating: !pours.isEmpty) else { continue }
            row.set(DayTotals(pours))
            if !pours.isEmpty { row.isAlcoholFree = false }
            tidy(row)
        }
    }

    /// Recomputes every day from scratch — after an import, or when the hour days end at changes (which moves
    /// entries between days). The same arithmetic as `refresh`, over everything.
    func rebuild(reassigningDays: Bool = false) {
        let pours = (try? context.fetch(FetchDescriptor<Pour>())) ?? []
        if reassigningDays {
            for pour in pours { pour.day = clock.day(for: pour.timestamp).number }
        }
        let byDay = Dictionary(grouping: pours, by: \.day)
        var rows = Dictionary(((try? context.fetch(FetchDescriptor<Day>())) ?? []).map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
        for (number, pours) in byDay {
            let row = rows[number] ?? {
                let row = Day(DayKey(number: number))
                context.insert(row)
                rows[number] = row
                return row
            }()
            row.set(DayTotals(pours))
            row.isAlcoholFree = false
        }
        for row in rows.values where byDay[row.number] == nil {
            row.set(DayTotals())
            tidy(row)
        }
        try? context.save()
    }

    private func row(for day: DayKey, creating: Bool) -> Day? {
        let number = day.number
        if let row = try? context.fetch(FetchDescriptor(predicate: #Predicate<Day> { $0.number == number })).first { return row }
        guard creating else { return nil }
        let row = Day(day)
        context.insert(row)
        return row
    }

    private func tidy(_ row: Day) {
        if row.count == 0 && !row.isAlcoholFree { context.delete(row) }
    }

    private func favourite(for serve: Serve) -> Favourite? {
        serve.favourite ?? serve.drink.favourites?.first { $0.vessel == serve.vessel && $0.volumeMl == serve.volumeMl }
    }
}

private extension Day {
    func set(_ totals: DayTotals) {
        units = totals.units
        kcal = totals.kcal
        cost = totals.cost
        count = totals.count
    }
}
