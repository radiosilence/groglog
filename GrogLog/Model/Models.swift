import Foundation
import GRDB

/// A drink's identity: name, type and strength. Sizes belong to Log-grid favourites and log entries, so one
/// Staropramen covers the 440 can and the 660 bottle. The default size and price are those it was first added with.
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

    /// The price in a given size. The stored price belongs to the size the drink was added in; other sizes are
    /// looked up in the catalogue rather than scaled, since Asahi is £7.40 a pint but £1.63 for a 330 ml bottle,
    /// not the £4.30 scaling would give. Only drinks unknown to the catalogue are scaled by volume.
    func price(for vessel: Vessel, ml: Double) -> Double {
        if vessel == self.vessel && ml == volumeMl { return price }
        if let known = Catalog.price(name: name, category: category, vessel: vessel, ml: ml) { return known }
        return price * ml / volumeMl
    }

    /// The sizes to offer, led by `size` when it is not among them: the catalogue's sizes for this drink, then its
    /// type's usual sizes. A type's sizes are a default, so Buckfast is offered in the 750 ml bottle it is sold in
    /// as well as the fortified-wine pours.
    func sizes(including size: ServeSize) -> [ServeSize] {
        var seen = Set<ServeSize>()
        let usual = (Catalog.sizes(name: name, category: category) + category.serves).filter { seen.insert($0).inserted }
        return usual.contains(size) ? usual : [size] + usual
    }
}

/// A drink in a particular size, pinned to the Log grid with its usual price.
nonisolated struct Favourite: Codable, Hashable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
    var id = UUID()
    var drinkId: UUID
    var vessel: Vessel
    var volumeMl: Double
    var price: Double
    var sortOrder = 0
    /// When it was last logged, for ordering by recent use without scanning history.
    var lastUsed: Date?

    static let drink = belongsTo(Drink.self)
}

/// A logged drink: which drink, plus when, what size and what it cost. Name, strength and type come from the
/// drink, so correcting a drink corrects everything logged as it, except where this one was logged at its own strength.
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
    /// Calories supplied by another app's import; otherwise they are derived from the drink.
    var kcalOverride: Double?
    /// The strength this one was logged at, when it differs from the drink's: a guest ale logged as Beer at the
    /// pump clip's 5.2%, without making a drink of it.
    var abvOverride: Double?

    static let drink = belongsTo(Drink.self)

    var dayKey: DayKey { DayKey(number: day) }
}

/// One drinking day's totals, kept in step with its entries by `Logbook`, plus whether it was marked alcohol-free.
/// Reports, the calendar and budgets read only these (a few hundred rows a year), never the entries. A day with
/// neither drinks nor a dry mark has no row.
nonisolated struct Day: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var number: Int
    var isAlcoholFree = false
    var units = 0.0
    var kcal = 0.0
    var cost = 0.0
    var count = 0
    /// A manually entered spend for the day, used instead of the sum of prices. When nil, spend is `cost`.
    var costOverride: Double?

    var key: DayKey { DayKey(number: number) }
    var spend: Double { costOverride ?? cost }
}

/// A log entry joined with its drink, as screens display it.
nonisolated struct Entry: Decodable, Hashable, Identifiable, Sendable, FetchableRecord {
    var pour: Pour
    var drink: Drink

    var id: UUID { pour.id }
    var name: String { drink.name }
    var category: DrinkCategory { drink.category }
    var abv: Double { pour.abvOverride ?? drink.abv }
    var vessel: Vessel { pour.vessel }
    var volumeMl: Double { pour.volumeMl }
    var price: Double { pour.price }
    var timestamp: Date { pour.timestamp }
    var day: Int { pour.day }
    var dayKey: DayKey { pour.dayKey }
    var units: Double { Units.of(ml: pour.volumeMl, abv: abv) }
    var kcal: Double { pour.kcalOverride ?? Units.kcal(ml: pour.volumeMl, abv: abv, category: drink.category) }
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

/// A drink in a size with its assumed price: the model behind a Log tile and the source of a new log entry.
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
