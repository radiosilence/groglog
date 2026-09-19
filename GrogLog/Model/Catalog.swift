import Foundation

/// Common UK drinks and their usual serves, so logging a specific brand is a search and a tap.
/// ABVs are typical UK figures and brands do quietly change them — anything logged from here becomes an editable drink.
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
    private typealias Serve = (vessel: Vessel, ml: Double)

    private static let pint: Serve = (.pint, 568)
    private static let half: Serve = (.half, 284)
    private static let can330: Serve = (.can, 330)
    private static let can440: Serve = (.can, 440)
    private static let can500: Serve = (.can, 500)
    private static let can568: Serve = (.can, 568)
    private static let bottle275: Serve = (.bottle, 275)
    private static let bottle330: Serve = (.bottle, 330)
    private static let bottle500: Serve = (.bottle, 500)
    private static let bottle568: Serve = (.bottle, 568)
    private static let bottle660: Serve = (.bottle, 660)
    private static let glass125: Serve = (.wineGlass, 125)
    private static let glass175: Serve = (.wineGlass, 175)
    private static let glass250: Serve = (.wineGlass, 250)
    private static let flute: Serve = (.flute, 125)
    private static let wineBottle: Serve = (.wineBottle, 750)
    private static let single: Serve = (.shot, 25)
    private static let double: Serve = (.tumbler, 50)

    private static let brands: [(String, DrinkCategory, Double, [Serve])] = [
        // Lager
        ("Stella Artois", .beer, 4.6, [pint, can440, can500, bottle330]),
        ("Carling", .beer, 3.7, [pint, can440, can568]),
        ("Foster's", .beer, 3.7, [pint, can440, can568]),
        ("Carlsberg", .beer, 3.8, [pint, can440]),
        ("Heineken", .beer, 5.0, [pint, can440, bottle330]),
        ("Peroni Nastro Azzurro", .beer, 5.0, [pint, bottle330, (.bottle, 620)]),
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
        ("Port", .fortified, 20.0, [(.wineGlass, 50)]),
        ("Sherry", .fortified, 15.0, [(.wineGlass, 70)]),
        // Spirits
        ("Gordon's Gin", .spirit, 37.5, [single, double]),
        ("Tanqueray", .spirit, 43.1, [single, double]),
        ("Bombay Sapphire", .spirit, 40.0, [single, double]),
        ("Smirnoff", .spirit, 37.5, [single, double]),
        ("Absolut", .spirit, 40.0, [single, double]),
        ("Jack Daniel's", .spirit, 40.0, [single, double]),
        ("Jameson", .spirit, 40.0, [single, double]),
        ("The Famous Grouse", .spirit, 40.0, [single, double]),
        ("Captain Morgan Spiced", .spirit, 35.0, [single, double]),
        ("Bacardi", .spirit, 37.5, [single, double]),
        ("Jägermeister", .spirit, 35.0, [single]),
        ("Tequila", .spirit, 38.0, [single]),
        ("Baileys", .spirit, 17.0, [(.tumbler, 50)]),
        // Mixed & ready-to-drink
        ("Gin & tonic", .cocktail, 4.2, [(.tumbler, 225)]),
        ("Double gin & tonic", .cocktail, 7.5, [(.tumbler, 250)]),
        ("Pimm's & lemonade", .cocktail, 5.0, [(.tumbler, 250)]),
        ("Aperol Spritz", .cocktail, 8.0, [(.wineGlass, 200)]),
        ("Espresso Martini", .cocktail, 15.0, [(.coupe, 120)]),
        ("Margarita", .cocktail, 16.0, [(.coupe, 150)]),
        ("Gordon's G&T can", .alcopop, 5.0, [(.can, 250)]),
        ("WKD", .alcopop, 4.0, [bottle275]),
        ("Smirnoff Ice", .alcopop, 4.0, [bottle275]),
        ("White Claw", .alcopop, 4.5, [can330]),
    ]

    static let items: [CatalogItem] = brands.flatMap { name, category, abv, serves in
        serves.map { CatalogItem(name: name, category: category, vessel: $0.vessel, volumeMl: $0.ml, abv: abv) }
    }

    static func search(_ query: String) -> [CatalogItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return items.filter { $0.name.localizedStandardContains(query) || $0.category.label.localizedStandardContains(query) }
    }
}
