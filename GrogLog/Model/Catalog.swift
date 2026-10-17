import Foundation
import GrogLogCore

/// A catalogue brand: common UK drinks and their usual serves, so logging a specific brand is a search and a tap.
/// The table, the prices and the lookups live in the shared core, which both apps read.
nonisolated struct CatalogBrand: Identifiable {
    let name: String
    let category: DrinkCategory
    let abv: Double
    /// Each usual size with its typical cost, per market, keyed by currency code.
    let prices: [String: [(size: ServeSize, price: Double)]]
    /// Every size any market lists it in, the UK's first.
    let sizes: [ServeSize]
    var id: String { name }

    init?(_ record: BrandRecord) {
        guard let category = DrinkCategory(rawValue: record.category) else { return nil }
        name = record.name
        self.category = category
        abv = record.abv
        prices = Dictionary(uniqueKeysWithValues: record.markets.map { market in
            (market.currency, market.serves.compactMap { serve in
                ServeSize(record: serve.vessel, serve.ml).map { (size: $0, price: serve.price) }
            })
        })
        sizes = record.sizes.compactMap { ServeSize(record: $0.vessel, $0.ml) }
    }
}

/// One brand in one of its usual sizes.
nonisolated struct CatalogItem: Identifiable, Hashable {
    let name: String
    let category: DrinkCategory
    let vessel: Vessel
    let volumeMl: Double
    let abv: Double

    /// The price in `currency`: from that market if the brand is sold there, otherwise converted from its home
    /// market.
    func price(in currency: String = Catalog.currency) -> Double {
        Catalog.price(name: name, category: category, vessel: vessel, ml: volumeMl, currency: currency) ?? 0
    }

    var id: String { "\(name)|\(vessel.rawValue)|\(Int(volumeMl))" }
    var units: Double { Units.of(ml: volumeMl, abv: abv) }
}

nonisolated extension ServeSize {
    fileprivate init?(record vessel: String, _ ml: Double) {
        guard let vessel = Vessel(rawValue: vessel) else { return nil }
        self.init(vessel, ml)
    }
}

nonisolated enum Catalog {
    static let brands: [CatalogBrand] = catalogBrands().compactMap(CatalogBrand.init)

    /// Every brand in every size; `search` answers with positions in this list.
    static let items: [CatalogItem] = catalogItems().compactMap { record in
        guard let category = DrinkCategory(rawValue: record.category), let vessel = Vessel(rawValue: record.vessel) else { return nil }
        return CatalogItem(name: record.name, category: category, vessel: vessel, volumeMl: record.ml, abv: record.abv)
    }

    /// The currency for prices: the one set in Setup, stored in the shared defaults so widgets and intents price the
    /// same way as the app.
    static var currency: String {
        UserDefaults.shared.string(forKey: "currency") ?? Locale.current.currency?.identifier ?? "GBP"
    }

    static let brandsByCategory: [DrinkCategory: [CatalogBrand]] = Dictionary(grouping: brands, by: \.category)

    /// A drink's identity as the catalogue sees it: same name, same kind.
    static func key(_ name: String, _ category: DrinkCategory) -> String { "\(name)|\(category.rawValue)" }

    /// Whether a drink still matches the catalogue exactly. Changing its name, kind or strength makes it the user's
    /// own.
    static func holds(name: String, category: DrinkCategory, abv: Double) -> Bool {
        catalogHolds(name: name, category: category.rawValue, abv: abv)
    }

    /// The sizes a drink of this name and kind is listed in, or none for a drink the catalogue does not know.
    static func sizes(name: String, category: DrinkCategory) -> [ServeSize] {
        catalogSizes(name: name, category: category.rawValue).compactMap { ServeSize(record: $0.vessel, $0.ml) }
    }

    /// The normal price of a drink of this name in this size: a brand's own price, else a generic's starting price.
    /// Nil when unknown, so callers can distinguish unpriced from free.
    static func price(name: String, category: DrinkCategory, vessel: Vessel, ml: Double, currency: String = currency) -> Double? {
        catalogPrice(name: name, category: category.rawValue, vessel: vessel.rawValue, ml: ml, currency: currency)
    }

    /// A size the brand is not listed in scales from the nearest serve of the same vessel first, and a drink sold in
    /// another currency's market is converted at the bundled rates.
    static func price(_ brand: CatalogBrand, _ vessel: Vessel, _ ml: Double, currency: String = currency) -> Double {
        catalogBrandPrice(name: brand.name, category: brand.category.rawValue, vessel: vessel.rawValue, ml: ml, currency: currency)
    }

    static func search(_ query: String) -> [CatalogItem] {
        catalogSearch(query: query).map { items[Int($0)] }
    }
}

nonisolated extension String {
    /// Case and accents folded, so "stella" finds Stella and "kolsch" finds Kölsch.
    var searchFolded: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
}
