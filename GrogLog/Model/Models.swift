import Foundation
import SwiftData

/// What a drink is: its name, type and strength. Sizes belong to picker items and log entries, so one Staropramen
/// covers the 440 can and the 660 bottle. The default size and price are what it was first added as.
@Model final class Drink {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = DrinkCategory.beer.rawValue
    var abv: Double = 4
    var vesselRaw: String = Vessel.pint.rawValue
    var volumeMl: Double = 568
    var price: Double = 0
    var isGeneric: Bool = false
    var isHidden: Bool = false
    var order: Int = 0
    @Relationship(deleteRule: .nullify, inverse: \Pour.drink) var pours: [Pour]? = []
    @Relationship(deleteRule: .cascade, inverse: \Favourite.drink) var favourites: [Favourite]? = []

    init(name: String, category: DrinkCategory, abv: Double, vessel: Vessel, volumeMl: Double, price: Double = 0, isGeneric: Bool = false, order: Int = 0) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.abv = abv
        self.vesselRaw = vessel.rawValue
        self.volumeMl = volumeMl
        self.price = price
        self.isGeneric = isGeneric
        self.order = order
    }

    var category: DrinkCategory {
        get { DrinkCategory(rawValue: categoryRaw) ?? .beer }
        set { categoryRaw = newValue.rawValue }
    }

    var vessel: Vessel {
        get { Vessel(rawValue: vesselRaw) ?? .pint }
        set { vesselRaw = newValue.rawValue }
    }

    /// The price to assume for a size: the default price scaled by volume.
    func price(forMl ml: Double) -> Double { price * ml / volumeMl }
}

/// A drink in a particular size, pinned to the Log grid with the price you usually pay for it.
@Model final class Favourite {
    var id: UUID = UUID()
    var vesselRaw: String = Vessel.pint.rawValue
    var volumeMl: Double = 568
    var price: Double = 0
    var order: Int = 0
    /// When it was last logged, for putting your usuals first without scanning history.
    var lastUsed: Date?
    var drink: Drink?

    init(drink: Drink, vessel: Vessel, volumeMl: Double, price: Double? = nil, order: Int = 0) {
        self.vesselRaw = vessel.rawValue
        self.volumeMl = volumeMl
        self.price = price ?? drink.price(forMl: volumeMl)
        self.order = order
        self.drink = drink
    }

    var vessel: Vessel { Vessel(rawValue: vesselRaw) ?? .pint }
}

/// A drink actually had: a reference to the drink, plus what's particular to this one — when, what size, and what it cost.
/// Name, strength and type are read from the drink, so correcting a drink corrects everything logged as it.
@Model final class Pour {
    #Index<Pour>([\.day], [\.timestamp])

    var id: UUID = UUID()
    var timestamp: Date = Date.now
    /// The drinking day (`DayKey.number`) it counted towards when logged, so entries are fetched by day and stay put across timezones.
    var day: Int = 0
    var vesselRaw: String = Vessel.pint.rawValue
    var volumeMl: Double = 0
    /// What it cost at the time. Prices change, so this is copied rather than read from the drink.
    var price: Double = 0
    /// Calories supplied by another app's import; otherwise they're worked out from the drink.
    var kcalOverride: Double?
    var drink: Drink?

    init(drink: Drink, at timestamp: Date, day: DayKey, vessel: Vessel? = nil, volumeMl: Double? = nil, price: Double? = nil, kcalOverride: Double? = nil, id: UUID = UUID()) {
        let volume = volumeMl ?? drink.volumeMl
        self.id = id
        self.timestamp = timestamp
        self.day = day.number
        self.vesselRaw = (vessel ?? drink.vessel).rawValue
        self.volumeMl = volume
        self.price = price ?? drink.price(forMl: volume)
        self.kcalOverride = kcalOverride
        self.drink = drink
    }


    var name: String { drink?.name ?? "Deleted drink" }
    var category: DrinkCategory { drink?.category ?? .units }
    var vessel: Vessel { Vessel(rawValue: vesselRaw) ?? .pint }
    var abv: Double { drink?.abv ?? 0 }
    var units: Double { Units.of(ml: volumeMl, abv: abv) }
    var kcal: Double { kcalOverride ?? Units.kcal(ml: volumeMl, abv: abv, category: category) }
    var serveKey: String { Serve.key(drink?.id, vessel, volumeMl) }
    var dayKey: DayKey { DayKey(number: day) }

    /// Entries for a range of drinking days, oldest first.
    static func on(_ days: ClosedRange<DayKey>) -> FetchDescriptor<Pour> {
        let (first, last) = (days.lowerBound.number, days.upperBound.number)
        return FetchDescriptor(predicate: #Predicate { $0.day >= first && $0.day <= last }, sortBy: [SortDescriptor(\.timestamp)])
    }
}

/// One drinking day's totals, kept in step with its entries by `Logbook`, plus whether it was marked alcohol-free.
/// Reports, the calendar and budgets read only these — a few hundred rows a year — never the entries themselves.
/// A day with neither drinks nor a dry mark has no row: it simply wasn't logged.
@Model final class Day {
    #Index<Day>([\.number])

    var number: Int = 0
    var isAlcoholFree: Bool = false
    var units: Double = 0
    var kcal: Double = 0
    var cost: Double = 0
    var count: Int = 0

    init(_ key: DayKey) {
        number = key.number
    }

    var key: DayKey { DayKey(number: number) }
}

/// A drink in a size, with the price to assume — what a Log tile is, and what a log entry is made from.
nonisolated struct Serve: Identifiable {
    let drink: Drink
    let vessel: Vessel
    let volumeMl: Double
    let price: Double
    var favourite: Favourite?

    init(_ drink: Drink, _ vessel: Vessel, _ volumeMl: Double, price: Double? = nil) {
        self.drink = drink
        self.vessel = vessel
        self.volumeMl = volumeMl
        self.price = price ?? drink.price(forMl: volumeMl)
    }

    init(_ favourite: Favourite) {
        self.init(favourite.drink!, favourite.vessel, favourite.volumeMl, price: favourite.price)
        self.favourite = favourite
    }

    /// The drink's default size.
    init(_ drink: Drink) {
        self.init(drink, drink.vessel, drink.volumeMl, price: drink.price)
    }

    var id: String { Self.key(drink.id, vessel, volumeMl) }
    var units: Double { Units.of(ml: volumeMl, abv: drink.abv) }

    static func key(_ drink: UUID?, _ vessel: Vessel, _ volumeMl: Double) -> String {
        "\(drink?.uuidString ?? "-")|\(vessel.rawValue)|\(Int(volumeMl))"
    }
}

extension ModelContext {
    /// The drink for bare unit counts (1 unit = 10 ml at 100%).
    func unitsDrink() -> Drink {
        let raw = DrinkCategory.units.rawValue
        if let drink = try? fetch(FetchDescriptor(predicate: #Predicate<Drink> { $0.categoryRaw == raw })).first { return drink }
        let drink = Drink(name: "Units", category: .units, abv: 100, vessel: .shot, volumeMl: 10, isGeneric: true, order: 99)
        insert(drink)
        return drink
    }

    /// The drink with this name and type, or a new one first had at this size.
    func drink(named name: String, category: DrinkCategory, abv: Double, vessel: Vessel, volumeMl: Double) -> Drink {
        let raw = category.rawValue
        if let drink = try? fetch(FetchDescriptor(predicate: #Predicate<Drink> { $0.name == name && $0.categoryRaw == raw })).first { return drink }
        let drink = Drink(name: name, category: category, abv: abv, vessel: vessel, volumeMl: volumeMl)
        insert(drink)
        return drink
    }

}
