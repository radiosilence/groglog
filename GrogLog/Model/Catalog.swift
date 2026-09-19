import Foundation

/// Common UK drinks and their usual serves, so logging a specific brand is a search and a tap.
/// ABVs are typical UK figures and brands do quietly change them — anything logged from here becomes an editable drink.
struct CatalogBrand: Identifiable {
    let name: String
    let category: DrinkCategory
    let abv: Double
    let serves: [ServeSize]
    var id: String { name }
}

/// One brand in one of its usual sizes.
struct CatalogItem: Identifiable, Hashable {
    let name: String
    let category: DrinkCategory
    let vessel: Vessel
    let volumeMl: Double
    let abv: Double

    var id: String { "\(name)|\(vessel.rawValue)|\(Int(volumeMl))" }
    var units: Double { Units.of(ml: volumeMl, abv: abv) }
}

enum Catalog {
    private static let pint = ServeSize(.pint, 568)
    private static let half = ServeSize(.half, 284)
    private static let can330 = ServeSize(.can, 330)
    private static let can440 = ServeSize(.can, 440)
    private static let can500 = ServeSize(.can, 500)
    private static let can568 = ServeSize(.can, 568)
    private static let bottle275 = ServeSize(.bottle, 275)
    private static let bottle330 = ServeSize(.bottle, 330)
    private static let bottle500 = ServeSize(.bottle, 500)
    private static let bottle568 = ServeSize(.bottle, 568)
    private static let bottle660 = ServeSize(.bottle, 660)
    private static let glass125 = ServeSize(.wineGlass, 125)
    private static let glass175 = ServeSize(.wineGlass, 175)
    private static let glass250 = ServeSize(.wineGlass, 250)
    private static let flute = ServeSize(.flute, 125)
    private static let wineBottle = ServeSize(.wineBottle, 750)
    private static let single = ServeSize(.shot, 25)
    private static let single35 = ServeSize(.shot, 35)
    private static let bottle70cl = ServeSize(.wineBottle, 700)

    private static let entries: [(String, DrinkCategory, Double, [ServeSize])] = [
        // Lager
        ("Stella Artois", .beer, 4.6, [pint, can440, can500, bottle330]),
        ("Carling", .beer, 3.7, [pint, can440, can568]),
        ("Foster's", .beer, 3.7, [pint, can440, can568]),
        ("Carlsberg", .beer, 3.8, [pint, can440]),
        ("Heineken", .beer, 5.0, [pint, can440, bottle330]),
        ("Peroni Nastro Azzurro", .beer, 5.0, [pint, bottle330, .init(.bottle, 620)]),
        ("Birra Moretti", .beer, 4.3, [pint, bottle330, can440]),
        ("Madrí", .beer, 4.6, [pint, can440]),
        ("Camden Hells", .beer, 4.6, [pint, can330]),
        ("Asahi Super Dry", .beer, 5.2, [pint, bottle330]),
        ("Corona", .beer, 4.5, [bottle330]),
        ("Budweiser", .beer, 4.5, [can440, bottle330]),
        ("Coors", .beer, 4.0, [pint, can440]),
        ("San Miguel", .beer, 5.0, [pint, bottle330, bottle660]),
        ("Cobra", .beer, 4.5, [pint, bottle330, bottle660]),
        ("Kingfisher", .beer, 4.8, [pint, bottle330, bottle660]),
        ("Kronenbourg 1664", .beer, 5.0, [pint, can440]),
        ("Estrella Damm", .beer, 4.6, [pint, bottle330]),
        ("Tennent's", .beer, 4.0, [pint, can440, can500]),
        ("Beck's", .beer, 4.0, [bottle330, can440]),
        // Ale & craft
        ("Beavertown Neck Oil", .beer, 4.3, [pint, can330]),
        ("Beavertown Gamma Ray", .beer, 5.4, [pint, can330]),
        ("BrewDog Punk IPA", .beer, 5.4, [pint, can330]),
        ("BrewDog Hazy Jane", .beer, 5.0, [pint, can330]),
        ("Gipsy Hill Hepcat", .beer, 4.6, [pint, can330]),
        ("Thornbridge Jaipur", .beer, 5.9, [pint, can330]),
        ("Lagunitas IPA", .beer, 6.2, [pint, can330]),
        ("Fuller's London Pride", .beer, 4.1, [pint, half]),
        ("Sharp's Doom Bar", .beer, 4.0, [pint, half]),
        ("Greene King IPA", .beer, 3.6, [pint, half]),
        ("Timothy Taylor's Landlord", .beer, 4.3, [pint, half]),
        ("Guinness", .stout, 4.2, [pint, half, can440]),
        // Cider
        ("Thatchers Gold", .cider, 4.8, [pint, can440, bottle500]),
        ("Thatchers Haze", .cider, 4.5, [pint, can440]),
        ("Strongbow", .cider, 4.5, [pint, can440]),
        ("Strongbow Dark Fruit", .cider, 4.0, [pint, can440]),
        ("Magners", .cider, 4.5, [pint, bottle568, can440]),
        ("Aspall", .cider, 5.5, [pint, can440]),
        ("Stowford Press", .cider, 4.5, [pint, can440]),
        ("Henry Westons Vintage", .cider, 8.2, [bottle500]),
        ("Westons Old Rosie", .cider, 7.3, [pint, bottle500]),
        ("Kopparberg Strawberry & Lime", .cider, 4.0, [bottle500]),
        ("Kopparberg Mixed Fruit", .cider, 4.0, [bottle500]),
        ("Old Mout Kiwi & Lime", .cider, 4.0, [bottle500]),
        // Wine
        ("Prosecco", .bubbles, 11.0, [flute, wineBottle]),
        ("Champagne", .bubbles, 12.0, [flute, wineBottle]),
        ("Cava", .bubbles, 11.5, [flute, wineBottle]),
        ("Pinot Grigio", .whiteWine, 12.0, [glass175, glass250, wineBottle]),
        ("Sauvignon Blanc", .whiteWine, 12.5, [glass175, glass250, wineBottle]),
        ("Chardonnay", .whiteWine, 13.0, [glass175, glass250, wineBottle]),
        ("Picpoul de Pinet", .whiteWine, 12.5, [glass175, wineBottle]),
        ("Rioja", .redWine, 13.5, [glass175, glass250, wineBottle]),
        ("Malbec", .redWine, 13.5, [glass175, glass250, wineBottle]),
        ("Merlot", .redWine, 13.5, [glass175, glass250, wineBottle]),
        ("Shiraz", .redWine, 14.0, [glass175, glass250, wineBottle]),
        ("Pinot Noir", .redWine, 13.0, [glass175, glass250, wineBottle]),
        ("Provence rosé", .rose, 12.5, [glass175, glass250, wineBottle]),
        ("Port", .fortified, 20.0, [.init(.wineGlass, 50)]),
        ("Sherry", .fortified, 15.0, [.init(.wineGlass, 70)]),
        // Spirits
        ("Gordon's Gin", .spirit, 37.5, [single, single35, bottle70cl]),
        ("Tanqueray", .spirit, 43.1, [single, single35, bottle70cl]),
        ("Bombay Sapphire", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Smirnoff", .spirit, 37.5, [single, single35, bottle70cl]),
        ("Absolut", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Jack Daniel's", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Jameson", .spirit, 40.0, [single, single35, bottle70cl]),
        ("The Famous Grouse", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Captain Morgan Spiced", .spirit, 35.0, [single, single35, bottle70cl]),
        ("Bacardi", .spirit, 37.5, [single, single35, bottle70cl]),
        ("Jägermeister", .spirit, 35.0, [single]),
        ("Tequila", .spirit, 38.0, [single]),
        ("Baileys", .spirit, 17.0, [.init(.tumbler, 50)]),
        // Mixed & ready-to-drink
        ("Gin & tonic", .cocktail, 4.2, [.init(.tumbler, 225)]),
        ("Double gin & tonic", .cocktail, 7.5, [.init(.tumbler, 250)]),
        ("Pimm's & lemonade", .cocktail, 5.0, [.init(.tumbler, 250)]),
        ("Aperol Spritz", .cocktail, 8.0, [.init(.wineGlass, 200)]),
        ("Espresso Martini", .cocktail, 15.0, [.init(.coupe, 120)]),
        ("Margarita", .cocktail, 16.0, [.init(.coupe, 150)]),
        ("Gordon's G&T can", .alcopop, 5.0, [.init(.can, 250)]),
        ("WKD", .alcopop, 4.0, [bottle275]),
        ("Smirnoff Ice", .alcopop, 4.0, [bottle275]),
        ("White Claw", .alcopop, 4.5, [can330]),
    ]

    static let brands: [CatalogBrand] = entries.map { CatalogBrand(name: $0.0, category: $0.1, abv: $0.2, serves: $0.3) }

    static let items: [CatalogItem] = brands.flatMap { brand in
        brand.serves.map { CatalogItem(name: brand.name, category: brand.category, vessel: $0.vessel, volumeMl: $0.ml, abv: brand.abv) }
    }

    static func search(_ query: String) -> [CatalogItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return items.filter { $0.name.localizedStandardContains(query) || $0.category.label.localizedStandardContains(query) }
    }
}
