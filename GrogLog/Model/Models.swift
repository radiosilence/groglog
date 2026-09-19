import Foundation
import SwiftData

/// Something you can log in one tap: a generic serve ("Pint of beer") or a specific one ("Hepcat, pint").
@Model final class Drink {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = DrinkCategory.beer.rawValue
    var vesselRaw: String = Vessel.pint.rawValue
    var volumeMl: Double = 568
    var abv: Double = 4
    var price: Double = 0
    var kcalOverride: Double?
    var isGeneric: Bool = false
    /// Favourite brands sit alongside the generics in the main picker; the rest are a long-press away.
    var isFavourite: Bool = false
    var isHidden: Bool = false
    var order: Int = 0
    @Relationship(deleteRule: .nullify, inverse: \Pour.drink) var pours: [Pour]? = []

    init(name: String, category: DrinkCategory, vessel: Vessel, volumeMl: Double, abv: Double, price: Double = 0, isGeneric: Bool = false, isFavourite: Bool = false, order: Int = 0) {
        self.name = name
        self.categoryRaw = category.rawValue
        self.vesselRaw = vessel.rawValue
        self.volumeMl = volumeMl
        self.abv = abv
        self.price = price
        self.isGeneric = isGeneric
        self.isFavourite = isFavourite
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

    var units: Double { Units.of(ml: volumeMl, abv: abv) }
    var kcal: Double { kcalOverride ?? Units.kcal(ml: volumeMl, abv: abv, category: category) }
}

/// A drink actually had: a reference to the drink, plus what's particular to this one — when, how much, and what it cost.
/// Name, strength and type are read from the drink, so correcting a drink corrects everything logged as it.
@Model final class Pour {
    var id: UUID = UUID()
    var timestamp: Date = Date.now
    /// The size actually poured, which can differ from the drink's usual serve.
    var volumeMl: Double = 0
    /// What it cost at the time. Prices change, so this is copied rather than read from the drink.
    var price: Double = 0
    /// Calories supplied by another app's import; otherwise they're worked out from the drink.
    var kcalOverride: Double?
    var drink: Drink?

    init(drink: Drink, at timestamp: Date, volumeMl: Double? = nil, price: Double? = nil, kcalOverride: Double? = nil, id: UUID = UUID()) {
        let volume = volumeMl ?? drink.volumeMl
        self.id = id
        self.timestamp = timestamp
        self.volumeMl = volume
        self.price = price ?? drink.price * volume / drink.volumeMl
        self.kcalOverride = kcalOverride
        self.drink = drink
    }

    var name: String { drink?.name ?? "Deleted drink" }
    var category: DrinkCategory { drink?.category ?? .units }
    var vessel: Vessel { drink?.vessel ?? .shot }
    var abv: Double { drink?.abv ?? 0 }
    var units: Double { Units.of(ml: volumeMl, abv: abv) }
    var kcal: Double { kcalOverride ?? Units.kcal(ml: volumeMl, abv: abv, category: category) }
}

/// An explicit "I didn't drink" marker. Its absence means the day wasn't logged, not that it was dry.
@Model final class AlcoholFreeDay {
    var day: Date = Date.distantPast

    init(day: Date) {
        self.day = day
    }
}

extension ModelContext {
    /// The drink for bare unit counts (1 unit = 10 ml at 100%).
    func unitsDrink() -> Drink {
        let raw = DrinkCategory.units.rawValue
        if let drink = try? fetch(FetchDescriptor(predicate: #Predicate<Drink> { $0.categoryRaw == raw })).first { return drink }
        let drink = Drink(name: "Units", category: .units, vessel: .shot, volumeMl: 10, abv: 100, isGeneric: true, order: 99)
        insert(drink)
        return drink
    }

    /// The drink with these details, or a new one hidden from the picker — for imports that name drinks this phone hasn't seen.
    func drink(named name: String, category: DrinkCategory, vessel: Vessel, volumeMl: Double, abv: Double) -> Drink {
        let raw = category.rawValue
        let matches = (try? fetch(FetchDescriptor(predicate: #Predicate<Drink> { $0.name == name && $0.categoryRaw == raw }))) ?? []
        if let drink = matches.first(where: { $0.abv == abv }) ?? matches.first { return drink }
        let drink = Drink(name: name, category: category, vessel: vessel, volumeMl: volumeMl, abv: abv)
        drink.isHidden = true
        insert(drink)
        return drink
    }

    func setAlcoholFree(_ dry: Bool, on day: Date) {
        let existing = (try? fetch(FetchDescriptor(predicate: #Predicate<AlcoholFreeDay> { $0.day == day }))) ?? []
        if dry, existing.isEmpty { insert(AlcoholFreeDay(day: day)) }
        if !dry { existing.forEach(delete) }
    }
}
