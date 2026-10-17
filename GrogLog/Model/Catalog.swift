import Foundation
import GrogLogCore

/// A catalogue brand: common UK drinks and their usual serves, so logging a specific brand is a search and a tap.
/// The table, the prices and the lookups live in the shared core, which both apps read.
nonisolated struct CatalogBrand: Identifiable {
    let name: String
    let category: DrinkCategory
    let abv: Double
    /// Every size any market lists it in, the UK's first.
    let sizes: [ServeSize]
    var id: String { name }

    init(_ record: BrandRecord) {
        name = record.name
        category = DrinkCategory(record.category)
        abv = record.abv
        sizes = record.sizes.map(ServeSize.init)
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
    fileprivate init(_ record: SizeRecord) {
        self.init(Vessel(record.vessel), record.ml)
    }
}

nonisolated enum Catalog {
    static let brands: [CatalogBrand] = catalogBrands().map(CatalogBrand.init)

    /// Every brand in every size, in the core's order, which `search` answers with positions into.
    static let items: [CatalogItem] = catalogItems().map { record in
        CatalogItem(name: record.name, category: DrinkCategory(record.category), vessel: Vessel(record.vessel), volumeMl: record.ml, abv: record.abv)
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
        catalogHolds(name: name, category: category.kind, abv: abv)
    }

    /// The sizes a drink of this name and kind is listed in, or none for a drink the catalogue does not know.
    static func sizes(name: String, category: DrinkCategory) -> [ServeSize] {
        catalogSizes(name: name, category: category.kind).map(ServeSize.init)
    }

    /// The normal price of a drink of this name in this size: a brand's own price, else a generic's starting price.
    /// Nil when unknown, so callers can distinguish unpriced from free.
    static func price(name: String, category: DrinkCategory, vessel: Vessel, ml: Double, currency: String = currency) -> Double? {
        catalogPrice(name: name, category: category.kind, vessel: vessel.kind, ml: ml, currency: currency)
    }

    /// A size the brand is not listed in scales from the nearest serve of the same vessel first, and a drink sold in
    /// another currency's market is converted at the bundled rates.
    static func price(_ brand: CatalogBrand, _ vessel: Vessel, _ ml: Double, currency: String = currency) -> Double {
        catalogBrandPrice(name: brand.name, category: brand.category.kind, vessel: vessel.kind, ml: ml, currency: currency)
    }

    static func search(_ query: String) -> [CatalogItem] {
        catalogSearch(query: query).map { items[Int($0)] }
    }
}
