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
    /// Each usual size with what it typically costs — a London bar price for a pint or a measure,
    /// a supermarket single-unit price for a can or a bottle.
    let serves: [(size: ServeSize, price: Double)]
    var id: String { name }
}

/// One brand in one of its usual sizes.
struct CatalogItem: Identifiable, Hashable {
    let name: String
    let category: DrinkCategory
    let vessel: Vessel
    let volumeMl: Double
    let abv: Double
    let price: Double

    var id: String { "\(name)|\(vessel.rawValue)|\(Int(volumeMl))" }
    var units: Double { Units.of(ml: volumeMl, abv: abv) }
}

enum Catalog {
    private static let pint = ServeSize(.pint, 568)
    private static let half = ServeSize(.half, 284)
    private static let can250 = ServeSize(.can, 250)
    private static let can330 = ServeSize(.can, 330)
    private static let can440 = ServeSize(.can, 440)
    private static let can500 = ServeSize(.can, 500)
    private static let can568 = ServeSize(.can, 568)
    private static let bottle275 = ServeSize(.bottle, 275)
    private static let bottle330 = ServeSize(.bottle, 330)
    private static let bottle500 = ServeSize(.bottle, 500)
    private static let bottle568 = ServeSize(.bottle, 568)
    private static let bottle620 = ServeSize(.bottle, 620)
    private static let bottle660 = ServeSize(.bottle, 660)
    private static let glass125 = ServeSize(.wineGlass, 125)
    private static let glass175 = ServeSize(.wineGlass, 175)
    private static let glass250 = ServeSize(.wineGlass, 250)
    private static let flute = ServeSize(.flute, 125)
    private static let wineBottle = ServeSize(.wineBottle, 750)
    private static let single = ServeSize(.shot, 25)
    private static let single35 = ServeSize(.shot, 35)
    private static let bottle70cl = ServeSize(.wineBottle, 700)
    private static let schooner = ServeSize(.wineGlass, 70)
    private static let port = ServeSize(.wineGlass, 50)
    private static let longDrink = ServeSize(.tumbler, 225)
    private static let doubleLong = ServeSize(.tumbler, 250)
    private static let rocks = ServeSize(.tumbler, 100)
    private static let coupe = ServeSize(.coupe, 150)
    private static let smallCoupe = ServeSize(.coupe, 120)

    /// Ordered by how often you'd reach for it, within each kind — the long-press sheet lists a whole
    /// category unfiltered, so the usual suspects come first and the long tail is a search away.
    private static let entries: [(String, DrinkCategory, Double, [(ServeSize, Double)])] = [
        // Lager — the pumps and multipacks
        ("Stella Artois", .beer, 4.6, [(pint, 6.4), (can440, 2.1), (can500, 2.4), (bottle330, 1.95)]),
        ("Carling", .beer, 4.0, [(pint, 6.4), (can440, 2.1), (can568, 2.7)]),
        ("Foster's", .beer, 3.7, [(pint, 6.4), (can440, 2.1), (can568, 2.7)]),
        ("Carlsberg", .beer, 3.4, [(pint, 6.4), (can440, 2.1)]),
        ("Carlsberg Export", .beer, 4.8, [(pint, 6.4), (can440, 2.1)]),
        ("Heineken", .beer, 5.0, [(pint, 6.4), (can440, 2.1), (bottle330, 1.95)]),
        ("Amstel", .beer, 4.1, [(pint, 6.4)]),
        ("Amstel (can)", .beer, 3.4, [(can440, 2.1)]),
        ("Kronenbourg 1664", .beer, 4.6, [(pint, 6.4), (can440, 2.1)]),
        ("Kronenbourg 1664 Blanc", .beer, 5.0, [(pint, 6.4), (bottle330, 1.95)]),
        ("Budweiser", .beer, 4.5, [(can440, 2.1), (bottle330, 1.95)]),
        ("Coors", .beer, 4.0, [(pint, 6.4), (can440, 2.1)]),
        ("Tennent's", .beer, 4.0, [(pint, 6.4), (can440, 2.1), (can500, 2.4)]),
        ("Beck's", .beer, 4.0, [(bottle330, 1.95), (can440, 2.1)]),
        ("Grolsch", .beer, 3.4, [(pint, 6.4), (can440, 2.1)]),
        ("Pravha", .beer, 4.0, [(pint, 6.4), (can440, 2.1)]),
        ("Staropramen", .beer, 5.0, [(pint, 6.4), (can440, 2.1), (bottle330, 1.95)]),
        // Imports
        ("Peroni Nastro Azzurro", .beer, 5.0, [(pint, 6.9), (bottle330, 2.2), (bottle620, 3.3)]),
        ("Birra Moretti", .beer, 4.6, [(pint, 6.9), (bottle330, 2.2), (can440, 2.35)]),
        ("Madrí", .beer, 4.6, [(pint, 6.9), (can440, 2.35)]),
        ("Estrella Damm", .beer, 4.6, [(pint, 6.9), (bottle330, 2.2)]),
        ("Estrella Galicia", .beer, 4.7, [(pint, 6.9), (bottle330, 2.2)]),
        ("San Miguel", .beer, 5.0, [(pint, 6.9), (bottle330, 2.2), (bottle660, 3.5)]),
        ("Mahou Cinco Estrellas", .beer, 4.8, [(pint, 6.9), (bottle330, 2.2)]),
        ("Cruzcampo", .beer, 4.4, [(pint, 6.9), (can440, 2.35)]),
        ("Poretti", .beer, 4.8, [(pint, 6.9), (bottle330, 2.2)]),
        ("Asahi Super Dry", .beer, 5.0, [(pint, 6.9), (bottle330, 2.2)]),
        ("Corona", .beer, 4.5, [(bottle330, 2.2)]),
        ("Sol", .beer, 4.2, [(bottle330, 2.2)]),
        ("Modelo Especial", .beer, 4.5, [(bottle330, 2.2)]),
        ("Desperados", .beer, 5.9, [(bottle330, 2.2)]),
        ("Cobra", .beer, 4.5, [(pint, 6.9), (bottle330, 2.2), (bottle660, 3.5)]),
        ("Kingfisher", .beer, 4.1, [(pint, 6.9)]),
        ("Kingfisher (bottle)", .beer, 4.5, [(bottle330, 2.2), (bottle660, 3.5)]),
        ("Tiger", .beer, 4.8, [(pint, 6.9), (bottle330, 2.2)]),
        ("Tsingtao", .beer, 4.7, [(bottle330, 2.2)]),
        ("Singha", .beer, 5.0, [(bottle330, 2.2)]),
        ("Red Stripe", .beer, 4.7, [(can440, 2.35), (bottle330, 2.2)]),
        // Craft pale & IPA
        ("Camden Hells", .beer, 4.6, [(pint, 7.2), (can330, 2.4)]),
        ("Camden Pale Ale", .beer, 4.0, [(pint, 7.2), (can330, 2.4)]),
        ("Beavertown Neck Oil", .beer, 4.3, [(pint, 7.2), (can330, 2.4)]),
        ("Beavertown Gamma Ray", .beer, 5.4, [(pint, 7.2), (can330, 2.4)]),
        ("BrewDog Punk IPA", .beer, 5.4, [(pint, 7.2), (can330, 2.4)]),
        ("BrewDog Hazy Jane", .beer, 5.0, [(pint, 7.2), (can330, 2.4)]),
        ("BrewDog Lost Lager", .beer, 4.5, [(pint, 7.2), (can330, 2.4)]),
        ("BrewDog Elvis Juice", .beer, 6.5, [(pint, 7.2), (can330, 2.4)]),
        ("Gipsy Hill Hepcat", .beer, 4.6, [(pint, 7.2), (can330, 2.4)]),
        ("Thornbridge Jaipur", .beer, 5.9, [(pint, 7.2), (can330, 2.4)]),
        ("Lagunitas IPA", .beer, 6.2, [(pint, 7.2), (can330, 2.4)]),
        ("Brooklyn Lager", .beer, 5.2, [(pint, 7.2), (can330, 2.4)]),
        ("Sierra Nevada Pale Ale", .beer, 5.6, [(pint, 7.2), (bottle330, 2.95)]),
        ("Sierra Nevada Pale Ale (can)", .beer, 5.0, [(can440, 3.15)]),
        ("Goose Island IPA", .beer, 5.9, [(pint, 7.2), (bottle330, 2.95)]),
        // Cask & bitter
        ("Fuller's London Pride", .beer, 4.1, [(pint, 5.9), (half, 2.95)]),
        ("Fuller's London Pride (bottle)", .beer, 4.7, [(bottle500, 3.1)]),
        ("Fuller's ESB", .beer, 5.5, [(pint, 5.9), (half, 2.95)]),
        ("Fuller's ESB (bottle)", .beer, 5.9, [(bottle500, 3.1)]),
        ("Sharp's Doom Bar", .beer, 4.0, [(pint, 5.9), (half, 2.95)]),
        ("Sharp's Doom Bar (bottle)", .beer, 4.3, [(bottle500, 3.1)]),
        ("Timothy Taylor's Landlord", .beer, 4.3, [(pint, 5.9), (half, 2.95)]),
        ("Timothy Taylor's Landlord (bottle)", .beer, 4.1, [(bottle500, 3.1)]),
        ("Greene King IPA", .beer, 3.6, [(pint, 5.9), (half, 2.95)]),
        ("Abbot Ale", .beer, 5.0, [(pint, 5.9), (half, 2.95)]),
        ("Old Speckled Hen", .beer, 4.5, [(pint, 5.9), (half, 2.95)]),
        ("Old Speckled Hen (bottle)", .beer, 4.8, [(bottle500, 3.1), (can500, 2.5)]),
        ("Bass", .beer, 4.4, [(pint, 5.9), (half, 2.95)]),
        ("Black Sheep Best Bitter", .beer, 3.8, [(pint, 5.9), (half, 2.95)]),
        ("Hobgoblin Ruby", .beer, 4.5, [(pint, 5.9), (half, 2.95)]),
        ("Hobgoblin Ruby (bottle)", .beer, 5.2, [(bottle500, 3.1)]),
        ("Adnams Ghost Ship", .beer, 4.5, [(pint, 5.9), (bottle500, 3.1)]),
        ("Marston's Pedigree", .beer, 4.5, [(pint, 5.9), (half, 2.95)]),
        ("Theakston Old Peculier", .beer, 5.6, [(pint, 5.9), (bottle500, 3.1)]),
        ("St Austell Tribute", .beer, 4.2, [(pint, 5.9), (half, 2.95)]),
        ("Wainwright", .beer, 4.1, [(pint, 5.9), (half, 2.95)]),
        ("Boddingtons", .beer, 3.5, [(pint, 5.9), (can440, 2.2)]),
        ("John Smith's Extra Smooth", .beer, 3.4, [(pint, 5.9), (can440, 2.2)]),
        ("Newcastle Brown Ale", .beer, 4.7, [(bottle500, 3.1)]),
        ("Titanic Plum Porter", .beer, 4.9, [(pint, 5.9), (bottle500, 3.1)]),
        // Wheat & Belgian
        ("Hoegaarden", .beer, 4.9, [(pint, 7), (bottle330, 2.8)]),
        ("Erdinger Weissbier", .beer, 5.3, [(pint, 7), (bottle500, 4.25)]),
        ("Paulaner Hefe-Weissbier", .beer, 5.5, [(pint, 7), (bottle500, 4.25)]),
        ("Blue Moon", .beer, 5.4, [(pint, 7), (bottle330, 2.8)]),
        ("Leffe Blonde", .beer, 6.6, [(bottle330, 2.8)]),
        ("Duvel", .beer, 8.5, [(bottle330, 2.8)]),
        // Stout
        ("Guinness", .stout, 4.2, [(pint, 6.3), (half, 3.15), (can440, 2.3)]),
        ("Guinness Extra Stout", .stout, 4.2, [(bottle330, 2.15)]),
        ("Murphy's", .stout, 4.0, [(pint, 6.3), (can440, 2.3)]),
        // Cider
        ("Thatchers Gold", .cider, 4.8, [(pint, 6.5), (can440, 2.2), (bottle500, 3.1)]),
        ("Thatchers Haze", .cider, 4.5, [(pint, 6.5), (can440, 2.2)]),
        ("Thatchers Blood Orange", .cider, 3.4, [(pint, 6.5), (can440, 2.2)]),
        ("Strongbow", .cider, 4.5, [(pint, 6.5), (can440, 2.2)]),
        ("Strongbow Dark Fruit", .cider, 4.0, [(pint, 6.5), (can440, 2.2)]),
        ("Bulmers Original", .cider, 4.5, [(pint, 6.5), (bottle568, 2.85)]),
        ("Magners", .cider, 4.5, [(pint, 6.5), (bottle568, 2.85), (can440, 2.2)]),
        ("Inch's", .cider, 4.5, [(pint, 6.5), (can440, 2.2)]),
        ("Aspall", .cider, 5.5, [(pint, 6.5), (can440, 2.2)]),
        ("Stowford Press", .cider, 4.5, [(pint, 6.5), (can440, 2.2)]),
        ("Cornish Orchards Gold", .cider, 5.0, [(pint, 6.5), (bottle500, 3.1)]),
        ("Henry Westons Vintage", .cider, 8.2, [(bottle500, 3.1)]),
        ("Westons Old Rosie", .cider, 6.8, [(pint, 6.5), (bottle500, 3.1)]),
        ("Kopparberg Strawberry & Lime", .cider, 4.0, [(bottle500, 3.1)]),
        ("Kopparberg Mixed Fruit", .cider, 4.0, [(bottle500, 3.1)]),
        ("Rekorderlig Strawberry & Lime", .cider, 4.0, [(bottle500, 3.1)]),
        ("Old Mout Kiwi & Lime", .cider, 4.0, [(bottle500, 3.1)]),
        // Fizz
        ("Prosecco", .bubbles, 11.0, [(flute, 8.5), (wineBottle, 9.5)]),
        ("Champagne", .bubbles, 12.0, [(flute, 8.5), (wineBottle, 9.5)]),
        ("Cava", .bubbles, 11.5, [(flute, 8.5), (wineBottle, 9.5)]),
        ("Crémant", .bubbles, 12.0, [(flute, 8.5), (wineBottle, 9.5)]),
        ("English sparkling", .bubbles, 12.0, [(flute, 8.5), (wineBottle, 9.5)]),
        ("Lambrusco", .bubbles, 8.0, [(flute, 8.5), (wineBottle, 9.5)]),
        ("Asti", .bubbles, 7.5, [(flute, 8.5), (wineBottle, 9.5)]),
        // Champagne worth the name
        ("Moët & Chandon Impérial", .bubbles, 12.0, [(flute, 14), (wineBottle, 48)]),
        ("Veuve Clicquot Yellow Label", .bubbles, 12.0, [(flute, 15), (wineBottle, 55)]),
        ("Bollinger Special Cuvée", .bubbles, 12.0, [(flute, 16), (wineBottle, 60)]),
        ("Laurent-Perrier Cuvée Rosé", .bubbles, 12.0, [(flute, 18), (wineBottle, 75)]),
        ("Taittinger Brut Réserve", .bubbles, 12.5, [(flute, 14), (wineBottle, 48)]),
        ("Pol Roger Brut Réserve", .bubbles, 12.5, [(flute, 15), (wineBottle, 52)]),
        ("Dom Pérignon", .bubbles, 12.5, [(flute, 40), (wineBottle, 190)]),
        ("Krug Grande Cuvée", .bubbles, 12.5, [(flute, 45), (wineBottle, 210)]),
        ("Louis Roederer Cristal", .bubbles, 12.0, [(flute, 50), (wineBottle, 250)]),
        // Once in a lifetime. Strengths come from auction listings, except the 1841, which was measured:
        // the bottles salvaged off Åland had fermented cool and slow and came out at 9%.
        ("Dom Pérignon P3 1971", .bubbles, 12.5, [(flute, 400), (wineBottle, 2500)]),
        ("Veuve Clicquot 1841 (Åland wreck)", .bubbles, 9.0, [(flute, 20000)]),
        // White
        ("Pinot Grigio", .whiteWine, 12.0, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Sauvignon Blanc", .whiteWine, 12.5, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Chardonnay", .whiteWine, 13.0, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Chablis", .whiteWine, 12.5, [(glass175, 8.5), (wineBottle, 9.5)]),
        ("Picpoul de Pinet", .whiteWine, 12.5, [(glass175, 8.5), (wineBottle, 9.5)]),
        ("Albariño", .whiteWine, 12.5, [(glass175, 8.5), (wineBottle, 9.5)]),
        ("Riesling", .whiteWine, 11.5, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Chenin Blanc", .whiteWine, 12.5, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Gavi", .whiteWine, 12.0, [(glass175, 8.5), (wineBottle, 9.5)]),
        ("Vinho Verde", .whiteWine, 10.5, [(glass175, 8.5), (wineBottle, 9.5)]),
        ("Viognier", .whiteWine, 13.0, [(glass175, 8.5), (wineBottle, 9.5)]),
        ("Château d'Yquem 1811", .whiteWine, 13.6, [(glass125, 3000), (wineBottle, 100000)]),
        // Red
        ("Rioja", .redWine, 13.5, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Malbec", .redWine, 13.5, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Merlot", .redWine, 13.5, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Shiraz", .redWine, 14.0, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Pinot Noir", .redWine, 13.0, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Cabernet Sauvignon", .redWine, 13.5, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Chianti", .redWine, 13.0, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Côtes du Rhône", .redWine, 14.0, [(glass175, 8.5), (wineBottle, 9.5)]),
        ("Primitivo", .redWine, 13.5, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Zinfandel", .redWine, 14.5, [(glass175, 8.5), (wineBottle, 9.5)]),
        ("Beaujolais", .redWine, 12.5, [(glass175, 8.5), (wineBottle, 9.5)]),
        ("Carménère", .redWine, 13.5, [(glass175, 8.5), (wineBottle, 9.5)]),
        ("Château Mouton Rothschild 1945", .redWine, 15.0, [(glass125, 2000), (wineBottle, 20000)]),
        ("Penfolds Grange 1951", .redWine, 12.3, [(glass125, 1500), (wineBottle, 12000)]),
        ("Screaming Eagle 1992", .redWine, 13.0, [(glass125, 500), (wineBottle, 5000)]),
        // Rosé
        ("Provence rosé", .rose, 12.5, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("Pinot Grigio rosé", .rose, 12.0, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        ("White Zinfandel", .rose, 10.5, [(glass175, 8.5), (glass250, 12.15), (wineBottle, 9.5)]),
        // Port, sherry & vermouth
        ("Port", .fortified, 20.0, [(port, 5.5)]),
        ("Madeira", .fortified, 19.0, [(port, 5.5)]),
        ("Sherry", .fortified, 15.0, [(schooner, 7.7)]),
        ("Cream sherry", .fortified, 17.5, [(schooner, 7.7)]),
        ("Vermouth", .fortified, 15.0, [(port, 5.5), (schooner, 7.7)]),
        ("Buckfast", .fortified, 15.0, [(glass175, 3.05), (wineBottle, 9)]),
        // Gin
        ("Gordon's Gin", .spirit, 37.5, [(single, 5), (single35, 7), (bottle70cl, 18)]),
        ("Gordon's Pink", .spirit, 37.5, [(single, 5), (single35, 7), (bottle70cl, 18)]),
        ("Tanqueray", .spirit, 41.3, [(single, 5.5), (single35, 7.7), (bottle70cl, 25)]),
        ("Bombay Sapphire", .spirit, 40.0, [(single, 5.5), (single35, 7.7), (bottle70cl, 24)]),
        ("Hendrick's", .spirit, 41.4, [(single, 6.5), (single35, 9.1), (bottle70cl, 32)]),
        ("Beefeater", .spirit, 40.0, [(single, 5), (single35, 7), (bottle70cl, 20)]),
        ("Whitley Neill Rhubarb & Ginger", .spirit, 43.0, [(single, 5.5), (single35, 7.7), (bottle70cl, 24)]),
        // Vodka
        ("Smirnoff", .spirit, 37.5, [(single, 5), (single35, 7), (bottle70cl, 18)]),
        ("Absolut", .spirit, 40.0, [(single, 5.2), (single35, 7.3), (bottle70cl, 22)]),
        ("Grey Goose", .spirit, 40.0, [(single, 7.5), (single35, 10.5), (bottle70cl, 42)]),
        // Whisky
        ("Jack Daniel's", .spirit, 40.0, [(single, 5.5), (single35, 7.7), (bottle70cl, 27)]),
        ("Jameson", .spirit, 40.0, [(single, 5.5), (single35, 7.7), (bottle70cl, 26)]),
        ("The Famous Grouse", .spirit, 40.0, [(single, 5), (single35, 7), (bottle70cl, 20)]),
        ("Bell's", .spirit, 40.0, [(single, 4.8), (single35, 6.7), (bottle70cl, 18)]),
        ("Johnnie Walker Black Label", .spirit, 40.0, [(single, 6.5), (single35, 9.1), (bottle70cl, 32)]),
        ("Monkey Shoulder", .spirit, 40.0, [(single, 6), (single35, 8.4), (bottle70cl, 30)]),
        ("Glenfiddich 12", .spirit, 40.0, [(single, 7), (single35, 9.8), (bottle70cl, 38)]),
        ("Glenmorangie", .spirit, 40.0, [(single, 7), (single35, 9.8), (bottle70cl, 38)]),
        ("Laphroaig 10", .spirit, 40.0, [(single, 7.5), (single35, 10.5), (bottle70cl, 45)]),
        ("Jim Beam", .spirit, 40.0, [(single, 5), (single35, 7), (bottle70cl, 22)]),
        ("Maker's Mark", .spirit, 45.0, [(single, 6.5), (single35, 9.1), (bottle70cl, 32)]),
        ("Bulleit Bourbon", .spirit, 45.0, [(single, 6.5), (single35, 9.1), (bottle70cl, 32)]),
        // Rum & tequila
        ("Bacardi", .spirit, 37.5, [(single, 5), (single35, 7), (bottle70cl, 20)]),
        ("Captain Morgan Spiced", .spirit, 35.0, [(single, 5), (single35, 7), (bottle70cl, 20)]),
        ("The Kraken", .spirit, 40.0, [(single, 5.5), (single35, 7.7), (bottle70cl, 24)]),
        ("Havana Club 3", .spirit, 40.0, [(single, 5), (single35, 7), (bottle70cl, 22)]),
        ("Malibu", .spirit, 18.0, [(single, 4.5), (single35, 6.3), (bottle70cl, 16.05)]),
        ("Tequila", .spirit, 38.0, [(single, 5), (single35, 7)]),
        // Liqueurs & aperitifs
        ("Baileys", .spirit, 17.0, [(port, 9.6)]),
        ("Jägermeister", .spirit, 35.0, [(single, 4.8)]),
        ("Disaronno", .spirit, 28.0, [(single, 4.8), (single35, 6.7)]),
        ("Cointreau", .spirit, 40.0, [(single, 4.8), (single35, 6.7)]),
        ("Southern Comfort", .spirit, 35.0, [(single, 4.8), (single35, 6.7)]),
        ("Tia Maria", .spirit, 20.0, [(single, 4.8), (single35, 6.7)]),
        ("Archers", .spirit, 18.0, [(single, 4.8), (single35, 6.7)]),
        ("Sambuca", .spirit, 38.0, [(single, 4.8)]),
        ("Fireball", .spirit, 33.0, [(single, 4.8)]),
        ("Courvoisier VS", .spirit, 40.0, [(single, 6.5), (single35, 9.1)]),
        ("Hennessy VS", .spirit, 40.0, [(single, 7), (single35, 9.8)]),
        ("Pimm's No. 1", .spirit, 22.0, [(single35, 6), (bottle70cl, 20)]),
        ("Aperol", .spirit, 11.0, [(single35, 5.5), (bottle70cl, 18)]),
        ("Campari", .spirit, 25.0, [(single, 5.5), (single35, 7.7)]),
        // Spirit & mixer, as poured
        ("Gin & tonic", .cocktail, 4.2, [(longDrink, 7.5)]),
        ("Double gin & tonic", .cocktail, 7.5, [(doubleLong, 10.5)]),
        ("Vodka & mixer", .cocktail, 4.2, [(longDrink, 7.5)]),
        ("Double vodka & mixer", .cocktail, 7.5, [(doubleLong, 10.5)]),
        ("Rum & Coke", .cocktail, 4.2, [(longDrink, 7.5)]),
        ("Double rum & Coke", .cocktail, 7.5, [(doubleLong, 10.5)]),
        ("Whisky & Coke", .cocktail, 4.2, [(longDrink, 7.5)]),
        ("Vodka Red Bull", .cocktail, 4.0, [(doubleLong, 9)]),
        ("Jägerbomb", .cocktail, 3.2, [(doubleLong, 6.5)]),
        ("Pimm's & lemonade", .cocktail, 5.0, [(doubleLong, 8.5)]),
        // Cocktails
        ("Aperol Spritz", .cocktail, 8.0, [(.init(.wineGlass, 200), 11)]),
        ("Espresso Martini", .cocktail, 15.0, [(smallCoupe, 13)]),
        ("Margarita", .cocktail, 16.0, [(coupe, 12.5)]),
        ("Mojito", .cocktail, 8.0, [(doubleLong, 12)]),
        ("Negroni", .cocktail, 24.0, [(rocks, 12.5)]),
        ("Old Fashioned", .cocktail, 32.0, [(.init(.tumbler, 70), 13)]),
        ("Cosmopolitan", .cocktail, 18.0, [(smallCoupe, 12)]),
        ("Porn Star Martini", .cocktail, 14.0, [(coupe, 13)]),
        ("Daiquiri", .cocktail, 20.0, [(smallCoupe, 12)]),
        ("Piña Colada", .cocktail, 8.0, [(doubleLong, 12)]),
        ("Long Island Iced Tea", .cocktail, 10.0, [(doubleLong, 13)]),
        ("Bloody Mary", .cocktail, 8.0, [(doubleLong, 11)]),
        ("Sangria", .cocktail, 9.0, [(glass250, 9)]),
        ("Buck's Fizz", .cocktail, 6.0, [(flute, 9)]),
        // Ready-to-drink
        ("Gordon's G&T can", .alcopop, 5.0, [(can250, 2.5)]),
        ("Gordon's Pink G&T can", .alcopop, 5.0, [(can250, 2.5)]),
        ("Bacardi & Cola can", .alcopop, 5.0, [(can250, 2.5)]),
        ("Captain Morgan & Cola can", .alcopop, 5.0, [(can250, 2.5)]),
        ("Jack Daniel's & Cola can", .alcopop, 5.0, [(can330, 3)]),
        ("White Claw", .alcopop, 4.5, [(can330, 2.2)]),
        ("WKD", .alcopop, 4.0, [(bottle275, 2)]),
        ("VK", .alcopop, 4.0, [(bottle275, 1.8)]),
        ("Smirnoff Ice", .alcopop, 4.0, [(bottle275, 2.2)]),
        ("Hooch", .alcopop, 4.0, [(bottle500, 2.5)]),
    ]

    static let brands: [CatalogBrand] = entries.map { CatalogBrand(name: $0.0, category: $0.1, abv: $0.2, serves: $0.3) }

    static let items: [CatalogItem] = brands.flatMap { brand in
        brand.serves.map { CatalogItem(name: brand.name, category: brand.category, vessel: $0.size.vessel, volumeMl: $0.size.ml, abv: brand.abv, price: $0.price) }
    }

    /// What a brand costs in a size it may not be listed in — its own price for that size, else the
    /// first serve scaled by volume, the same way a drink's own price scales.
    static func price(_ brand: CatalogBrand, _ vessel: Vessel, _ ml: Double) -> Double {
        if let exact = brand.serves.first(where: { $0.size.vessel == vessel && $0.size.ml == ml }) { return exact.price }
        guard let first = brand.serves.first else { return 0 }
        return first.price * ml / first.size.ml
    }

    static func search(_ query: String) -> [CatalogItem] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return items.filter { $0.name.localizedStandardContains(query) || $0.category.label.localizedStandardContains(query) }
    }
}
