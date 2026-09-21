import Foundation
import GRDB

/// What a drink is: its name, type and strength. Sizes belong to Log-grid favourites and log entries, so one
/// Staropramen covers the 440 can and the 660 bottle. The default size and price are what it was first added as.
nonisolated struct Drink: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    var id = UUID()
    var name: String
    var category: DrinkCategory
    var abv: Double
    var vessel: Vessel
    var volumeMl: Double
    var price = 0.0
    var isGeneric = false
    var isHidden = false
    var sortOrder = 0

    /// What this costs in a size. The price it carries belongs to the size it was added in; another size
    /// is another product at another price, so that one gets looked up rather than worked out from this
    /// one. Asahi is £7.40 a pint and £1.63 for the 330 ml bottle, and dividing the pint by volume says
    /// £4.30. Only a drink of your own invention, which the catalogue has never heard of, gets scaled —
    /// there being nothing else to go on.
    func price(for vessel: Vessel, ml: Double) -> Double {
        if vessel == self.vessel && ml == volumeMl { return price }
        if let known = Catalog.price(name: name, category: category, vessel: vessel, ml: ml) { return known }
        return price * ml / volumeMl
    }
}

/// A drink in a particular size, pinned to the Log grid with the price you usually pay for it.
nonisolated struct Favourite: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    var id = UUID()
    var drinkId: UUID
    var vessel: Vessel
    var volumeMl: Double
    var price: Double
    var sortOrder = 0
    /// When it was last logged, for putting your usuals first without scanning history.
    var lastUsed: Date?

    static let drink = belongsTo(Drink.self)
}

/// A drink actually had: which drink, plus what's particular to this one — when, what size, what it cost.
/// Name, strength and type come from the drink, so correcting a drink corrects everything logged as it.
nonisolated struct Pour: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    var id = UUID()
    var drinkId: UUID
    var timestamp: Date
    /// The drinking day (`DayKey.number`) it counted towards when logged, so entries are fetched by day and stay put across timezones.
    var day: Int
    var vessel: Vessel
    var volumeMl: Double
    /// What it cost at the time. Prices change, so this is copied rather than read from the drink.
    var price: Double
    /// Calories supplied by another app's import; otherwise they're worked out from the drink.
    var kcalOverride: Double?

    static let drink = belongsTo(Drink.self)

    var dayKey: DayKey { DayKey(number: day) }
}

/// One drinking day's totals, kept in step with its entries by `Logbook`, plus whether it was marked alcohol-free.
/// Reports, the calendar and budgets read only these — a few hundred rows a year — never the entries themselves.
/// A day with neither drinks nor a dry mark has no row: it simply wasn't logged.
nonisolated struct Day: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var number: Int
    var isAlcoholFree = false
    var units = 0.0
    var kcal = 0.0
    var cost = 0.0
    var count = 0
    /// What the day actually cost, when the drinks' prices aren't worth keeping straight. Cleared, spend falls back to `cost`.
    var costOverride: Double?

    var key: DayKey { DayKey(number: number) }
    var spend: Double { costOverride ?? cost }
}

/// A log entry with its drink — what screens show.
nonisolated struct Entry: Decodable, Hashable, Identifiable, Sendable, FetchableRecord {
    var pour: Pour
    var drink: Drink

    var id: UUID { pour.id }
    var name: String { drink.name }
    var category: DrinkCategory { drink.category }
    var abv: Double { drink.abv }
    var vessel: Vessel { pour.vessel }
    var volumeMl: Double { pour.volumeMl }
    var price: Double { pour.price }
    var timestamp: Date { pour.timestamp }
    var day: Int { pour.day }
    var dayKey: DayKey { pour.dayKey }
    var units: Double { Units.of(ml: pour.volumeMl, abv: drink.abv) }
    var kcal: Double { pour.kcalOverride ?? Units.kcal(ml: pour.volumeMl, abv: drink.abv, category: drink.category) }
    var serveKey: String { Serve.key(drink.id, pour.vessel, pour.volumeMl) }
}

/// A favourite with its drink.
nonisolated struct FavouriteItem: Decodable, Hashable, Sendable, FetchableRecord {
    var favourite: Favourite
    var drink: Drink

    var serve: Serve {
        var serve = Serve(drink, favourite.vessel, favourite.volumeMl, price: favourite.price)
        serve.favourite = favourite
        return serve
    }
}

/// A drink in a size, with the price to assume — what a Log tile is, and what a log entry is made from.
nonisolated struct Serve: Identifiable, Hashable, Sendable {
    let drink: Drink
    let vessel: Vessel
    let volumeMl: Double
    let price: Double
    var favourite: Favourite?

    init(_ drink: Drink, _ vessel: Vessel, _ volumeMl: Double, price: Double? = nil) {
        self.drink = drink
        self.vessel = vessel
        self.volumeMl = volumeMl
        self.price = price ?? drink.price(for: vessel, ml: volumeMl)
    }

    /// The drink's default size.
    init(_ drink: Drink) {
        self.init(drink, drink.vessel, drink.volumeMl, price: drink.price)
    }

    var id: String { Self.key(drink.id, vessel, volumeMl) }
    var units: Double { Units.of(ml: volumeMl, abv: drink.abv) }

    static func key(_ drink: UUID, _ vessel: Vessel, _ volumeMl: Double) -> String {
        "\(drink.uuidString)|\(vessel.rawValue)|\(Int(volumeMl))"
    }
}
