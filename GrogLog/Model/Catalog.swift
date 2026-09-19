import Foundation

/// Common UK drinks and their usual serves, so logging a specific brand is a search and a tap.
/// ABVs are the UK label figures. A brand brewed at two strengths is two entries — cask London Pride is 4.1%,
/// the bottle 4.7% — because a drink is one strength and rounding the difference away costs you a unit a night.
/// Brands do quietly change strength (the 3.5% duty threshold has pulled a lot of lagers down to 3.4%), so
/// anything logged from here becomes an editable drink of your own.
struct CatalogBrand: Identifiable {
    let name: String
    let category: DrinkCategory
    let abv: Double
    let serves: [(vessel: Vessel, ml: Double)]
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
    private typealias Size = (vessel: Vessel, ml: Double)

    private static let pint: Size = (.pint, 568)
    private static let half: Size = (.half, 284)
    private static let can250: Size = (.can, 250)
    private static let can330: Size = (.can, 330)
    private static let can440: Size = (.can, 440)
    private static let can500: Size = (.can, 500)
    private static let can568: Size = (.can, 568)
    private static let bottle275: Size = (.bottle, 275)
    private static let bottle330: Size = (.bottle, 330)
    private static let bottle500: Size = (.bottle, 500)
    private static let bottle568: Size = (.bottle, 568)
    private static let bottle620: Size = (.bottle, 620)
    private static let bottle660: Size = (.bottle, 660)
    private static let glass125: Size = (.wineGlass, 125)
    private static let glass175: Size = (.wineGlass, 175)
    private static let glass250: Size = (.wineGlass, 250)
    private static let flute: Size = (.flute, 125)
    private static let wineBottle: Size = (.wineBottle, 750)
    private static let single: Size = (.shot, 25)
    private static let single35: Size = (.shot, 35)
    private static let bottle70cl: Size = (.wineBottle, 700)
    private static let schooner: Size = (.wineGlass, 70)
    private static let port: Size = (.wineGlass, 50)
    private static let longDrink: Size = (.tumbler, 225)
    private static let doubleLong: Size = (.tumbler, 250)
    private static let rocks: Size = (.tumbler, 100)
    private static let coupe: Size = (.coupe, 150)
    private static let smallCoupe: Size = (.coupe, 120)

    /// Ordered by how often you'd reach for it, within each kind — the long-press sheet lists a whole
    /// category unfiltered, so the usual suspects come first and the long tail is a search away.
    private static let entries: [(String, DrinkCategory, Double, [Size])] = [
        // Lager — the pumps and multipacks
        ("Stella Artois", .beer, 4.6, [pint, can440, can500, bottle330]),
        ("Carling", .beer, 4.0, [pint, can440, can568]),
        ("Foster's", .beer, 3.7, [pint, can440, can568]),
        ("Carlsberg", .beer, 3.4, [pint, can440]),
        ("Carlsberg Export", .beer, 4.8, [pint, can440]),
        ("Heineken", .beer, 5.0, [pint, can440, bottle330]),
        ("Amstel", .beer, 4.1, [pint]),
        ("Amstel (can)", .beer, 3.4, [can440]),
        ("Kronenbourg 1664", .beer, 4.6, [pint, can440]),
        ("Kronenbourg 1664 Blanc", .beer, 5.0, [pint, bottle330]),
        ("Budweiser", .beer, 4.5, [can440, bottle330]),
        ("Coors", .beer, 4.0, [pint, can440]),
        ("Tennent's", .beer, 4.0, [pint, can440, can500]),
        ("Beck's", .beer, 4.0, [bottle330, can440]),
        ("Grolsch", .beer, 3.4, [pint, can440]),
        ("Pravha", .beer, 4.0, [pint, can440]),
        ("Staropramen", .beer, 5.0, [pint, can440, bottle330]),
        // Imports
        ("Peroni Nastro Azzurro", .beer, 5.0, [pint, bottle330, bottle620]),
        ("Birra Moretti", .beer, 4.6, [pint, bottle330, can440]),
        ("Madrí", .beer, 4.6, [pint, can440]),
        ("Estrella Damm", .beer, 4.6, [pint, bottle330]),
        ("Estrella Galicia", .beer, 4.7, [pint, bottle330]),
        ("San Miguel", .beer, 5.0, [pint, bottle330, bottle660]),
        ("Mahou Cinco Estrellas", .beer, 4.8, [pint, bottle330]),
        ("Cruzcampo", .beer, 4.4, [pint, can440]),
        ("Poretti", .beer, 4.8, [pint, bottle330]),
        ("Asahi Super Dry", .beer, 5.0, [pint, bottle330]),
        ("Corona", .beer, 4.5, [bottle330]),
        ("Sol", .beer, 4.2, [bottle330]),
        ("Modelo Especial", .beer, 4.5, [bottle330]),
        ("Desperados", .beer, 5.9, [bottle330]),
        ("Cobra", .beer, 4.5, [pint, bottle330, bottle660]),
        ("Kingfisher", .beer, 4.1, [pint]),
        ("Kingfisher (bottle)", .beer, 4.5, [bottle330, bottle660]),
        ("Tiger", .beer, 4.8, [pint, bottle330]),
        ("Tsingtao", .beer, 4.7, [bottle330]),
        ("Singha", .beer, 5.0, [bottle330]),
        ("Red Stripe", .beer, 4.7, [can440, bottle330]),
        // Craft pale & IPA
        ("Camden Hells", .beer, 4.6, [pint, can330]),
        ("Camden Pale Ale", .beer, 4.0, [pint, can330]),
        ("Beavertown Neck Oil", .beer, 4.3, [pint, can330]),
        ("Beavertown Gamma Ray", .beer, 5.4, [pint, can330]),
        ("BrewDog Punk IPA", .beer, 5.4, [pint, can330]),
        ("BrewDog Hazy Jane", .beer, 5.0, [pint, can330]),
        ("BrewDog Lost Lager", .beer, 4.5, [pint, can330]),
        ("BrewDog Elvis Juice", .beer, 6.5, [pint, can330]),
        ("Gipsy Hill Hepcat", .beer, 4.6, [pint, can330]),
        ("Thornbridge Jaipur", .beer, 5.9, [pint, can330]),
        ("Lagunitas IPA", .beer, 6.2, [pint, can330]),
        ("Brooklyn Lager", .beer, 5.2, [pint, can330]),
        ("Sierra Nevada Pale Ale", .beer, 5.6, [pint, bottle330]),
        ("Sierra Nevada Pale Ale (can)", .beer, 5.0, [can440]),
        ("Goose Island IPA", .beer, 5.9, [pint, bottle330]),
        // Cask & bitter
        ("Fuller's London Pride", .beer, 4.1, [pint, half]),
        ("Fuller's London Pride (bottle)", .beer, 4.7, [bottle500]),
        ("Fuller's ESB", .beer, 5.5, [pint, half]),
        ("Fuller's ESB (bottle)", .beer, 5.9, [bottle500]),
        ("Sharp's Doom Bar", .beer, 4.0, [pint, half]),
        ("Sharp's Doom Bar (bottle)", .beer, 4.3, [bottle500]),
        ("Timothy Taylor's Landlord", .beer, 4.3, [pint, half]),
        ("Timothy Taylor's Landlord (bottle)", .beer, 4.1, [bottle500]),
        ("Greene King IPA", .beer, 3.6, [pint, half]),
        ("Abbot Ale", .beer, 5.0, [pint, half]),
        ("Old Speckled Hen", .beer, 4.5, [pint, half]),
        ("Old Speckled Hen (bottle)", .beer, 4.8, [bottle500, can500]),
        ("Bass", .beer, 4.4, [pint, half]),
        ("Black Sheep Best Bitter", .beer, 3.8, [pint, half]),
        ("Hobgoblin Ruby", .beer, 4.5, [pint, half]),
        ("Hobgoblin Ruby (bottle)", .beer, 5.2, [bottle500]),
        ("Adnams Ghost Ship", .beer, 4.5, [pint, bottle500]),
        ("Marston's Pedigree", .beer, 4.5, [pint, half]),
        ("Theakston Old Peculier", .beer, 5.6, [pint, bottle500]),
        ("St Austell Tribute", .beer, 4.2, [pint, half]),
        ("Wainwright", .beer, 4.1, [pint, half]),
        ("Boddingtons", .beer, 3.5, [pint, can440]),
        ("John Smith's Extra Smooth", .beer, 3.4, [pint, can440]),
        ("Newcastle Brown Ale", .beer, 4.7, [bottle500]),
        ("Titanic Plum Porter", .beer, 4.9, [pint, bottle500]),
        // Wheat & Belgian
        ("Hoegaarden", .beer, 4.9, [pint, bottle330]),
        ("Erdinger Weissbier", .beer, 5.3, [pint, bottle500]),
        ("Paulaner Hefe-Weissbier", .beer, 5.5, [pint, bottle500]),
        ("Blue Moon", .beer, 5.4, [pint, bottle330]),
        ("Leffe Blonde", .beer, 6.6, [bottle330]),
        ("Duvel", .beer, 8.5, [bottle330]),
        // Stout
        ("Guinness", .stout, 4.2, [pint, half, can440]),
        ("Guinness Extra Stout", .stout, 4.2, [bottle330]),
        ("Murphy's", .stout, 4.0, [pint, can440]),
        // Cider
        ("Thatchers Gold", .cider, 4.8, [pint, can440, bottle500]),
        ("Thatchers Haze", .cider, 4.5, [pint, can440]),
        ("Thatchers Blood Orange", .cider, 3.4, [pint, can440]),
        ("Strongbow", .cider, 4.5, [pint, can440]),
        ("Strongbow Dark Fruit", .cider, 4.0, [pint, can440]),
        ("Bulmers Original", .cider, 4.5, [pint, bottle568]),
        ("Magners", .cider, 4.5, [pint, bottle568, can440]),
        ("Inch's", .cider, 4.5, [pint, can440]),
        ("Aspall", .cider, 5.5, [pint, can440]),
        ("Stowford Press", .cider, 4.5, [pint, can440]),
        ("Cornish Orchards Gold", .cider, 5.0, [pint, bottle500]),
        ("Henry Westons Vintage", .cider, 8.2, [bottle500]),
        ("Westons Old Rosie", .cider, 6.8, [pint, bottle500]),
        ("Kopparberg Strawberry & Lime", .cider, 4.0, [bottle500]),
        ("Kopparberg Mixed Fruit", .cider, 4.0, [bottle500]),
        ("Rekorderlig Strawberry & Lime", .cider, 4.0, [bottle500]),
        ("Old Mout Kiwi & Lime", .cider, 4.0, [bottle500]),
        // Fizz
        ("Prosecco", .bubbles, 11.0, [flute, wineBottle]),
        ("Champagne", .bubbles, 12.0, [flute, wineBottle]),
        ("Cava", .bubbles, 11.5, [flute, wineBottle]),
        ("Crémant", .bubbles, 12.0, [flute, wineBottle]),
        ("English sparkling", .bubbles, 12.0, [flute, wineBottle]),
        ("Lambrusco", .bubbles, 8.0, [flute, wineBottle]),
        ("Asti", .bubbles, 7.5, [flute, wineBottle]),
        // White
        ("Pinot Grigio", .whiteWine, 12.0, [glass175, glass250, wineBottle]),
        ("Sauvignon Blanc", .whiteWine, 12.5, [glass175, glass250, wineBottle]),
        ("Chardonnay", .whiteWine, 13.0, [glass175, glass250, wineBottle]),
        ("Chablis", .whiteWine, 12.5, [glass175, wineBottle]),
        ("Picpoul de Pinet", .whiteWine, 12.5, [glass175, wineBottle]),
        ("Albariño", .whiteWine, 12.5, [glass175, wineBottle]),
        ("Riesling", .whiteWine, 11.5, [glass175, glass250, wineBottle]),
        ("Chenin Blanc", .whiteWine, 12.5, [glass175, glass250, wineBottle]),
        ("Gavi", .whiteWine, 12.0, [glass175, wineBottle]),
        ("Vinho Verde", .whiteWine, 10.5, [glass175, wineBottle]),
        ("Viognier", .whiteWine, 13.0, [glass175, wineBottle]),
        // Red
        ("Rioja", .redWine, 13.5, [glass175, glass250, wineBottle]),
        ("Malbec", .redWine, 13.5, [glass175, glass250, wineBottle]),
        ("Merlot", .redWine, 13.5, [glass175, glass250, wineBottle]),
        ("Shiraz", .redWine, 14.0, [glass175, glass250, wineBottle]),
        ("Pinot Noir", .redWine, 13.0, [glass175, glass250, wineBottle]),
        ("Cabernet Sauvignon", .redWine, 13.5, [glass175, glass250, wineBottle]),
        ("Chianti", .redWine, 13.0, [glass175, glass250, wineBottle]),
        ("Côtes du Rhône", .redWine, 14.0, [glass175, wineBottle]),
        ("Primitivo", .redWine, 13.5, [glass175, glass250, wineBottle]),
        ("Zinfandel", .redWine, 14.5, [glass175, wineBottle]),
        ("Beaujolais", .redWine, 12.5, [glass175, wineBottle]),
        ("Carménère", .redWine, 13.5, [glass175, wineBottle]),
        // Rosé
        ("Provence rosé", .rose, 12.5, [glass175, glass250, wineBottle]),
        ("Pinot Grigio rosé", .rose, 12.0, [glass175, glass250, wineBottle]),
        ("White Zinfandel", .rose, 10.5, [glass175, glass250, wineBottle]),
        // Port, sherry & vermouth
        ("Port", .fortified, 20.0, [port]),
        ("Madeira", .fortified, 19.0, [port]),
        ("Sherry", .fortified, 15.0, [schooner]),
        ("Cream sherry", .fortified, 17.5, [schooner]),
        ("Vermouth", .fortified, 15.0, [port, schooner]),
        ("Buckfast", .fortified, 15.0, [glass175, wineBottle]),
        // Gin
        ("Gordon's Gin", .spirit, 37.5, [single, single35, bottle70cl]),
        ("Gordon's Pink", .spirit, 37.5, [single, single35, bottle70cl]),
        ("Tanqueray", .spirit, 41.3, [single, single35, bottle70cl]),
        ("Bombay Sapphire", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Hendrick's", .spirit, 41.4, [single, single35, bottle70cl]),
        ("Beefeater", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Whitley Neill Rhubarb & Ginger", .spirit, 43.0, [single, single35, bottle70cl]),
        // Vodka
        ("Smirnoff", .spirit, 37.5, [single, single35, bottle70cl]),
        ("Absolut", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Grey Goose", .spirit, 40.0, [single, single35, bottle70cl]),
        // Whisky
        ("Jack Daniel's", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Jameson", .spirit, 40.0, [single, single35, bottle70cl]),
        ("The Famous Grouse", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Bell's", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Johnnie Walker Black Label", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Monkey Shoulder", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Glenfiddich 12", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Glenmorangie", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Laphroaig 10", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Jim Beam", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Maker's Mark", .spirit, 45.0, [single, single35, bottle70cl]),
        ("Bulleit Bourbon", .spirit, 45.0, [single, single35, bottle70cl]),
        // Rum & tequila
        ("Bacardi", .spirit, 37.5, [single, single35, bottle70cl]),
        ("Captain Morgan Spiced", .spirit, 35.0, [single, single35, bottle70cl]),
        ("The Kraken", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Havana Club 3", .spirit, 40.0, [single, single35, bottle70cl]),
        ("Malibu", .spirit, 18.0, [single, single35, bottle70cl]),
        ("Tequila", .spirit, 38.0, [single, single35]),
        // Liqueurs & aperitifs
        ("Baileys", .spirit, 17.0, [port]),
        ("Jägermeister", .spirit, 35.0, [single]),
        ("Disaronno", .spirit, 28.0, [single, single35]),
        ("Cointreau", .spirit, 40.0, [single, single35]),
        ("Southern Comfort", .spirit, 35.0, [single, single35]),
        ("Tia Maria", .spirit, 20.0, [single, single35]),
        ("Archers", .spirit, 18.0, [single, single35]),
        ("Sambuca", .spirit, 38.0, [single]),
        ("Fireball", .spirit, 33.0, [single]),
        ("Courvoisier VS", .spirit, 40.0, [single, single35]),
        ("Hennessy VS", .spirit, 40.0, [single, single35]),
        ("Pimm's No. 1", .spirit, 22.0, [single35, bottle70cl]),
        ("Aperol", .spirit, 11.0, [single35, bottle70cl]),
        ("Campari", .spirit, 25.0, [single, single35]),
        // Spirit & mixer, as poured
        ("Gin & tonic", .cocktail, 4.2, [longDrink]),
        ("Double gin & tonic", .cocktail, 7.5, [doubleLong]),
        ("Vodka & mixer", .cocktail, 4.2, [longDrink]),
        ("Double vodka & mixer", .cocktail, 7.5, [doubleLong]),
        ("Rum & Coke", .cocktail, 4.2, [longDrink]),
        ("Double rum & Coke", .cocktail, 7.5, [doubleLong]),
        ("Whisky & Coke", .cocktail, 4.2, [longDrink]),
        ("Vodka Red Bull", .cocktail, 4.0, [doubleLong]),
        ("Jägerbomb", .cocktail, 3.2, [doubleLong]),
        ("Pimm's & lemonade", .cocktail, 5.0, [doubleLong]),
        // Cocktails
        ("Aperol Spritz", .cocktail, 8.0, [(.wineGlass, 200)]),
        ("Espresso Martini", .cocktail, 15.0, [smallCoupe]),
        ("Margarita", .cocktail, 16.0, [coupe]),
        ("Mojito", .cocktail, 8.0, [doubleLong]),
        ("Negroni", .cocktail, 24.0, [rocks]),
        ("Old Fashioned", .cocktail, 32.0, [(.tumbler, 70)]),
        ("Cosmopolitan", .cocktail, 18.0, [smallCoupe]),
        ("Porn Star Martini", .cocktail, 14.0, [coupe]),
        ("Daiquiri", .cocktail, 20.0, [smallCoupe]),
        ("Piña Colada", .cocktail, 8.0, [doubleLong]),
        ("Long Island Iced Tea", .cocktail, 10.0, [doubleLong]),
        ("Bloody Mary", .cocktail, 8.0, [doubleLong]),
        ("Sangria", .cocktail, 9.0, [glass250]),
        ("Buck's Fizz", .cocktail, 6.0, [flute]),
        // Ready-to-drink
        ("Gordon's G&T can", .alcopop, 5.0, [can250]),
        ("Gordon's Pink G&T can", .alcopop, 5.0, [can250]),
        ("Bacardi & Cola can", .alcopop, 5.0, [can250]),
        ("Captain Morgan & Cola can", .alcopop, 5.0, [can250]),
        ("Jack Daniel's & Cola can", .alcopop, 5.0, [can330]),
        ("White Claw", .alcopop, 4.5, [can330]),
        ("WKD", .alcopop, 4.0, [bottle275]),
        ("VK", .alcopop, 4.0, [bottle275]),
        ("Smirnoff Ice", .alcopop, 4.0, [bottle275]),
        ("Hooch", .alcopop, 4.0, [bottle500]),
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
