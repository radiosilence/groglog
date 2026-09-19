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

/// A drink actually consumed. Snapshots the drink's details so editing a drink never rewrites history.
@Model final class Pour {
    var id: UUID = UUID()
    var timestamp: Date = Date.now
    var name: String = ""
    var categoryRaw: String = DrinkCategory.beer.rawValue
    var vesselRaw: String = Vessel.pint.rawValue
    var volumeMl: Double = 0
    var abv: Double = 0
    var price: Double = 0
    var kcal: Double = 0
    var drinkID: UUID?

    init(id: UUID = UUID(), timestamp: Date, name: String, category: DrinkCategory, vessel: Vessel, volumeMl: Double, abv: Double, price: Double, kcal: Double, drinkID: UUID?) {
        self.id = id
        self.timestamp = timestamp
        self.name = name
        self.categoryRaw = category.rawValue
        self.vesselRaw = vessel.rawValue
        self.volumeMl = volumeMl
        self.abv = abv
        self.price = price
        self.kcal = kcal
        self.drinkID = drinkID
    }

    /// Logs `drink`, optionally in a different size — price and calories scale with it.
    convenience init(drink: Drink, at timestamp: Date, volumeMl: Double? = nil) {
        let scale = (volumeMl ?? drink.volumeMl) / drink.volumeMl
        self.init(timestamp: timestamp, name: drink.name, category: drink.category, vessel: drink.vessel, volumeMl: drink.volumeMl * scale, abv: drink.abv, price: drink.price * scale, kcal: drink.kcal * scale, drinkID: drink.id)
    }

    var category: DrinkCategory { DrinkCategory(rawValue: categoryRaw) ?? .beer }
    var vessel: Vessel { Vessel(rawValue: vesselRaw) ?? .pint }
    var units: Double { Units.of(ml: volumeMl, abv: abv) }

    func recalculateKcal() {
        kcal = Units.kcal(ml: volumeMl, abv: abv, category: category)
    }
}

extension Pour {
    /// A bare unit count: 1 unit is 10 ml of pure alcohol.
    convenience init(units: Double, at timestamp: Date, kcal: Double? = nil, price: Double = 0, drinkID: UUID? = nil, id: UUID = UUID()) {
        self.init(id: id, timestamp: timestamp, name: "Units", category: .units, vessel: .shot, volumeMl: units * 10, abv: 100, price: price, kcal: kcal ?? Units.kcal(ml: units * 10, abv: 100, category: .units), drinkID: drinkID)
    }
}

/// An explicit "I didn't drink" marker. Its absence means the day wasn't logged, not that it was dry.
@Model final class AlcoholFreeDay {
    var day: Date = Date.distantPast

    init(day: Date) {
        self.day = day
    }
}

extension ModelContext {
    func setAlcoholFree(_ dry: Bool, on day: Date) {
        let existing = (try? fetch(FetchDescriptor(predicate: #Predicate<AlcoholFreeDay> { $0.day == day }))) ?? []
        if dry, existing.isEmpty { insert(AlcoholFreeDay(day: day)) }
        if !dry { existing.forEach(delete) }
    }
}
