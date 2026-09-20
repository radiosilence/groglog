import Foundation

/// Common UK drinks and their usual serves, so logging a specific brand is a search and a tap.
/// ABVs are the UK label figures. A brand brewed at two strengths is two entries — cask London Pride is 4.1%,
/// the bottle 4.7% — because a drink is one strength and rounding the difference away costs you a unit a night.
/// Brands do quietly change strength (the 3.5% duty threshold has pulled a lot of lagers down to 3.4%), so
/// anything logged from here becomes an editable drink of your own.
nonisolated struct CatalogBrand: Identifiable {
    let name: String
    let category: DrinkCategory
    let abv: Double
    /// Each usual size with what it typically costs — a London bar price for a pint, a glass or a
    /// measure, a supermarket single price for a can or a bottle. Two kinds of figure aren't a lookup.
    /// Pubs price draught and by-the-glass by tier rather than by brand, and per-venue prices are
    /// barely published, so a brand with no menu of its own takes its tier's price. And mainstream
    /// lager and cider don't sell as single cans here at all, only multipacks, so those carry the
    /// multipack's unit rate — roughly half what one can costs, where anyone sells you one.
    let serves: [(size: ServeSize, price: Double)]
    var id: String { name }
}

/// One brand in one of its usual sizes.
nonisolated struct CatalogItem: Identifiable, Hashable {
    let name: String
    let category: DrinkCategory
    let vessel: Vessel
    let volumeMl: Double
    let abv: Double
    let price: Double

    var id: String { "\(name)|\(vessel.rawValue)|\(Int(volumeMl))" }
    var units: Double { Units.of(ml: volumeMl, abv: abv) }
}

nonisolated enum Catalog {
    private static let pint = ServeSize(.pint, 568)
    private static let half = ServeSize(.half, 284)
    private static let can250 = ServeSize(.can, 250)
    private static let can330 = ServeSize(.can, 330)
    private static let can355 = ServeSize(.can, 355)
    private static let can440 = ServeSize(.can, 440)
    private static let can480 = ServeSize(.can, 480)
    private static let can500 = ServeSize(.can, 500)
    private static let can568 = ServeSize(.can, 568)
    private static let bottle275 = ServeSize(.bottle, 275)
    private static let bottle330 = ServeSize(.bottle, 330)
    private static let bottle350 = ServeSize(.bottle, 350)
    private static let bottle355 = ServeSize(.bottle, 355)
    private static let bottle440 = ServeSize(.bottle, 440)
    private static let bottle500 = ServeSize(.bottle, 500)
    private static let bottle568 = ServeSize(.bottle, 568)
    private static let bottle620 = ServeSize(.bottle, 620)
    private static let bottle650 = ServeSize(.bottle, 650)
    private static let bottle660 = ServeSize(.bottle, 660)
    private static let bottle2500 = ServeSize(.bottle, 2500)
    private static let glass125 = ServeSize(.wineGlass, 125)
    private static let glass175 = ServeSize(.wineGlass, 175)
    private static let glass250 = ServeSize(.wineGlass, 250)
    private static let flute = ServeSize(.flute, 125)
    private static let halfBottle = ServeSize(.wineBottle, 350)
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
        ("Stella Artois", .beer, 4.6, [(pint, 6.7), (can440, 0.85), (can500, 0.85), (bottle330, 1.13)]),
        ("Carling", .beer, 4.0, [(pint, 6.2), (can440, 1.23), (can568, 1.38)]),
        ("Foster's", .beer, 3.7, [(pint, 5.9), (can440, 0.75), (can568, 1.19)]),
        ("Carlsberg", .beer, 3.4, [(pint, 5.9), (can440, 0.74)]),
        ("Carlsberg Export", .beer, 4.8, [(pint, 6.2), (can440, 2.05)]),
        ("Heineken", .beer, 5.0, [(pint, 6.2), (can440, 0.9), (bottle330, 1.17)]),
        ("Amstel", .beer, 4.1, [(pint, 6.5)]),
        ("Amstel (can)", .beer, 3.4, [(can440, 0.58)]),
        ("Kronenbourg 1664", .beer, 4.6, [(pint, 6.2), (can440, 1.19)]),
        ("Kronenbourg 1664 Blanc", .beer, 5.0, [(pint, 6.2), (bottle330, 1.59)]),
        ("Budweiser", .beer, 4.5, [(can440, 0.85), (bottle330, 1.44)]),
        ("Coors", .beer, 4.0, [(pint, 5.9), (can440, 0.7)]),
        ("Tennent's", .beer, 4.0, [(pint, 6.2), (can440, 1.63), (can500, 1.38)]),
        ("Beck's", .beer, 4.0, [(bottle330, 0.81), (can440, 0.81)]),
        ("Grolsch", .beer, 3.4, [(pint, 6.2), (can440, 1.13)]),
        ("Pravha", .beer, 4.0, [(pint, 6), (bottle660, 2.85)]),
        ("Staropramen", .beer, 5.0, [(pint, 6.2), (can440, 1.25), (bottle330, 1.75)]),
        // Imports
        ("Peroni Nastro Azzurro", .beer, 5.0, [(pint, 7.2), (bottle330, 1.5), (bottle620, 2.88)]),
        ("Birra Moretti", .beer, 4.6, [(pint, 7), (bottle330, 1), (can440, 1)]),
        ("Madrí", .beer, 4.6, [(pint, 6.9), (can440, 1.38)]),
        ("Estrella Damm", .beer, 4.6, [(pint, 6.7), (bottle330, 1.17)]),
        ("Estrella Galicia", .beer, 4.7, [(pint, 6.7), (bottle330, 1.47)]),
        ("San Miguel", .beer, 5.0, [(pint, 6.8), (bottle330, 1.95), (bottle620, 2.48)]),
        ("Mahou Cinco Estrellas", .beer, 4.8, [(pint, 7), (bottle330, 1.5)]),
        ("Cruzcampo", .beer, 4.4, [(pint, 6.45), (can440, 1.13)]),
        ("Poretti", .beer, 4.8, [(pint, 7), (bottle330, 0.96)]),
        ("Asahi Super Dry", .beer, 5.0, [(pint, 7.4), (bottle330, 1.63)]),
        ("Corona", .beer, 4.5, [(bottle330, 1.08)]),
        ("Sol", .beer, 4.2, [(bottle330, 0.67)]),
        ("Modelo Especial", .beer, 4.5, [(bottle330, 1.75)]),
        ("Desperados", .beer, 5.9, [(bottle330, 1.75)]),
        ("Cobra", .beer, 4.5, [(pint, 7), (bottle330, 1.75), (bottle620, 2.77)]),
        ("Kingfisher", .beer, 4.1, [(pint, 7)]),
        ("Kingfisher (bottle)", .beer, 4.5, [(bottle330, 1.75), (bottle650, 2.85)]),
        ("Tiger", .beer, 4.8, [(pint, 7.1), (bottle330, 1.75)]),
        ("Tsingtao", .beer, 4.7, [(bottle330, 1.42)]),
        ("Singha", .beer, 5.0, [(bottle330, 1.67)]),
        ("Red Stripe", .beer, 4.7, [(can440, 1.5), (bottle330, 1.25)]),
        // Polish. "Mocne" is the strong version of a beer and a separate entry, not a rounding of
        // the standard one — Perła Chmielowa is 6%, Perła Mocna 7.1%.
        ("Tyskie Gronie", .beer, 5.2, [(can500, 1.29), (bottle650, 2.55)]),
        ("Żywiec", .beer, 5.6, [(can500, 1.99)]),
        ("Żywiec Białe", .beer, 4.9, [(bottle500, 1.54)]),
        ("Żywiec Porter", .beer, 9.5, [(bottle500, 2.7)]),
        ("Lech Premium", .beer, 4.8, [(can500, 1.79)]),
        ("Okocim Jasne", .beer, 5.1, [(can500, 2.04)]),
        ("Okocim Mocne", .beer, 6.5, [(can500, 2.29)]),
        ("Warka Classic", .beer, 5.2, [(can500, 1.99)]),
        ("Warka Strong", .beer, 6.5, [(can500, 1.67)]),
        ("Perła Chmielowa", .beer, 6.0, [(bottle500, 2.1)]),
        ("Perła Mocna", .beer, 7.1, [(can500, 1.89)]),
        ("Łomża Export", .beer, 5.7, [(can500, 1.99)]),
        ("Harnaś", .beer, 6.0, [(can500, 1.99)]),
        ("Dębowe Mocne", .beer, 7.0, [(can500, 1.74)]),
        ("Żubr", .beer, 6.0, [(can500, 1.99)]),
        ("Tatra", .beer, 6.0, [(can500, 1.83)]),
        ("Namysłów Pils", .beer, 5.8, [(can500, 1.83), (bottle500, 2)]),
        ("Kasztelan Jasne Pełne", .beer, 5.7, [(can500, 2.19)]),
        ("Książęce Złote Pszeniczne", .beer, 4.9, [(bottle500, 2.96)]),
        // Czech, Baltic & the Balkans. No Russian beer: the UK bans importing it, so what's still listed
        // is old stock. Ukrainian is another matter — Chernigivske is an AB InBev relief import, in Asda.
        ("Pilsner Urquell", .beer, 4.4, [(pint, 6.05), (bottle500, 2.7)]),
        ("Budweiser Budvar", .beer, 5.0, [(bottle500, 2.5)]),
        ("Velkopopovický Kozel", .beer, 4.6, [(can500, 2.25)]),
        ("Velkopopovický Kozel Černý", .beer, 3.8, [(can500, 2.18)]),
        ("Krušovice Original", .beer, 4.2, [(can500, 2.5)]),
        ("Utenos", .beer, 5.0, [(bottle500, 2.44)]),
        ("Švyturys Ekstra", .beer, 5.2, [(can568, 1.85)]),
        ("Kalnapilis Original", .beer, 5.4, [(can568, 2.87)]),
        ("Aldaris Zelta Premium", .beer, 5.2, [(bottle500, 2.84)]),
        ("Volfas Engelman Rinktinis", .beer, 5.2, [(can568, 2.5)]),
        ("Lvivske 1715", .beer, 4.5, [(can480, 2.46)]),
        ("Chernigivske", .beer, 4.8, [(can440, 1)]),
        ("Ožujsko", .beer, 5.0, [(bottle330, 3.29)]),
        ("Nikšićko", .beer, 5.0, [(bottle330, 2.71), (can500, 2.88)]),
        ("Laško Zlatorog", .beer, 4.9, [(bottle330, 2.69)]),
        ("Timișoreana", .beer, 5.0, [(bottle500, 1.89)]),
        ("Ursus Premium", .beer, 5.0, [(can500, 3.29)]),
        ("Ciucaș", .beer, 4.6, [(bottle330, 1.45), (can500, 2.5)]),
        ("Kamenitza", .beer, 4.4, [(bottle500, 2.49)]),
        ("Dreher Gold", .beer, 4.8, [(bottle500, 3.5)]),
        ("Soproni Classic", .beer, 4.5, [(bottle500, 3.5)]),
        ("Borsodi", .beer, 4.5, [(bottle500, 3.5)]),
        // Craft pale & IPA
        ("Camden Hells", .beer, 4.6, [(pint, 7.05), (can330, 2.25)]),
        ("Camden Pale Ale", .beer, 4.0, [(pint, 6.3), (can330, 2.25)]),
        ("Beavertown Neck Oil", .beer, 4.3, [(pint, 6.92), (can330, 2.2)]),
        ("Beavertown Gamma Ray", .beer, 5.4, [(pint, 6.9), (can330, 2.35)]),
        ("BrewDog Punk IPA", .beer, 5.4, [(pint, 7.05), (can330, 1.99)]),
        ("BrewDog Hazy Jane", .beer, 5.0, [(pint, 7.05), (can330, 1.99)]),
        ("BrewDog Lost Lager", .beer, 4.5, [(pint, 6.9), (can440, 1.75)]),
        ("BrewDog Elvis Juice", .beer, 6.5, [(pint, 7.5), (can330, 2.19)]),
        ("Gipsy Hill Hepcat", .beer, 4.6, [(pint, 6.9), (can330, 2.95)]),
        ("Thornbridge Jaipur", .beer, 5.9, [(pint, 7), (can330, 2.25)]),
        ("Lagunitas IPA", .beer, 6.2, [(pint, 7), (bottle355, 1.28)]),
        ("Brooklyn Lager", .beer, 5.2, [(pint, 6.9), (can330, 1.8)]),
        ("Sierra Nevada Pale Ale", .beer, 5.6, [(pint, 7), (bottle350, 1.39)]),
        ("Sierra Nevada Pale Ale (can)", .beer, 5.0, [(can355, 2.32)]),
        ("Goose Island IPA", .beer, 5.9, [(pint, 7), (bottle330, 1.5)]),
        // London craft, mostly by the can: these breweries are all over London taps but hardly any of
        // those menus are published, so only the three taprooms that post a price carry one and the
        // rest fall back to the can's rate by volume rather than to a made-up bar figure. Fourpure,
        // Magic Rock and Brick are all gone — Fourpure's brewing moved to Magic Rock shortly before
        // Magic Rock shut, and Brick dissolved in June 2025, which is why there's no Peckham Pils.
        // Meantime renamed two of these: London Lager is Greenwich Lager, London Pale Ale is Prime Pale.
        ("Meantime Greenwich Lager", .beer, 4.5, [(bottle330, 1.58)]),
        ("Meantime Prime Pale", .beer, 4.3, [(can330, 1.63)]),
        ("Meantime Yakima Red", .beer, 4.5, [(can440, 2)]),
        ("Camden Off Menu IPA", .beer, 5.8, [(pint, 6.75), (can330, 1.8)]),
        ("Wolfpack Lager", .beer, 5.0, [(pint, 5.2)]),
        ("Wolfpack Pilsner", .beer, 4.4, [(pint, 5)]),
        ("Brixton Reliance Pale Ale", .beer, 4.2, [(can330, 1.5)]),
        ("Brixton Coldharbour Lager", .beer, 4.4, [(can330, 1.18)]),
        ("Anspach & Hobday The London Black", .beer, 4.4, [(can440, 4.6)]),
        ("Anspach & Hobday Table Beer", .beer, 2.7, [(can440, 2.95)]),
        ("Five Points XPA", .beer, 4.0, [(can330, 2.99)]),
        ("Five Points Railway Porter", .beer, 4.8, [(can330, 2.95)]),
        ("Signature Brew Studio Lager", .beer, 4.0, [(can330, 1.58)]),
        ("Villages Rodeo", .beer, 4.6, [(pint, 4), (can330, 2.8)]),
        ("Villages Rafiki", .beer, 4.3, [(can330, 3.2)]),
        ("Orbit Peel", .beer, 4.9, [(bottle330, 2.63)]),
        ("Pressure Drop Pale Fire", .beer, 4.8, [(can440, 3.85)]),
        ("Howling Hops Tropical Deluxe", .beer, 3.8, [(pint, 5.9), (can440, 3.2)]),
        ("Howling Hops Barley Pop", .beer, 4.4, [(can440, 3.1)]),
        ("Deya Steady Rolling Man", .beer, 5.2, [(half, 3), (can500, 4.5)]),
        ("Cloudwater DDH Pale", .beer, 5.0, [(can440, 4.75)]),
        ("Northern Monk Faith", .beer, 5.0, [(can440, 3)]),
        ("Track Sonoma", .beer, 3.8, [(can440, 4)]),
        ("Siren Lumina", .beer, 4.2, [(can330, 2.2)]),
        ("Siren Broken Dream", .stout, 6.5, [(can330, 2.3)]),
        // Cask & bitter
        ("Fuller's London Pride", .beer, 4.1, [(pint, 5.6), (half, 2.8)]),
        ("Fuller's London Pride (bottle)", .beer, 4.7, [(bottle500, 2.35)]),
        ("Fuller's ESB", .beer, 5.5, [(pint, 5.3), (half, 2.65)]),
        ("Fuller's ESB (bottle)", .beer, 5.9, [(bottle500, 2.45)]),
        ("Sharp's Doom Bar", .beer, 4.0, [(pint, 5.55), (half, 2.8)]),
        ("Sharp's Doom Bar (bottle)", .beer, 4.3, [(bottle500, 1.75)]),
        ("Timothy Taylor's Landlord", .beer, 4.3, [(pint, 5.1), (half, 2.55)]),
        ("Timothy Taylor's Landlord (bottle)", .beer, 4.1, [(bottle500, 2.45)]),
        ("Greene King IPA", .beer, 3.6, [(pint, 4.2), (half, 2.1)]),
        ("Abbot Ale", .beer, 5.0, [(pint, 4.65), (half, 2.35)]),
        ("Old Speckled Hen", .beer, 4.5, [(pint, 5.6), (half, 2.8)]),
        ("Old Speckled Hen (bottle)", .beer, 4.8, [(bottle500, 2.5), (can500, 1.5)]),
        ("Bass", .beer, 4.4, [(pint, 5.4), (half, 2.7)]),
        ("Black Sheep Best Bitter", .beer, 3.8, [(pint, 4.45), (half, 2.25)]),
        ("Hobgoblin Ruby", .beer, 4.5, [(pint, 4.98), (half, 2.5)]),
        ("Hobgoblin Ruby (bottle)", .beer, 5.2, [(bottle500, 1.7)]),
        ("Adnams Ghost Ship", .beer, 4.5, [(pint, 5.15), (bottle500, 1.75)]),
        ("Marston's Pedigree", .beer, 4.5, [(pint, 4.98), (half, 2.5)]),
        ("Theakston Old Peculier", .beer, 5.6, [(pint, 5.3), (bottle500, 2.4)]),
        ("St Austell Tribute", .beer, 4.2, [(pint, 5.07), (half, 2.55)]),
        ("Wainwright", .beer, 4.1, [(pint, 4.45), (half, 2.25)]),
        ("Boddingtons", .beer, 3.5, [(pint, 4.2), (can440, 1.15)]),
        ("John Smith's Extra Smooth", .beer, 3.4, [(pint, 4.2), (can440, 1.35)]),
        ("Newcastle Brown Ale", .beer, 4.7, [(bottle500, 1.75)]),
        ("Titanic Plum Porter", .beer, 4.9, [(pint, 5.2), (bottle500, 2.5)]),
        // Wheat & Belgian
        ("Hoegaarden", .beer, 4.9, [(pint, 6.9), (bottle330, 1.79)]),
        ("Erdinger Weissbier", .beer, 5.3, [(pint, 7.2), (bottle500, 1.75)]),
        ("Paulaner Hefe-Weissbier", .beer, 5.5, [(pint, 7.2), (bottle500, 1.8)]),
        ("Blue Moon", .beer, 5.4, [(pint, 6.9), (bottle330, 1.65)]),
        // Belgian, priced as a bar pours it rather than as a shop sells it, because that's how anyone
        // drinks these. The Porterhouse in Covent Garden is the one London Belgian bar that publishes
        // a price list, and twelve of these come straight off it. The rest take its price for their
        // strength: £7 for an abbey blonde, £7.40 at 8.5%, £7.70 at 9%, £8.90 for Rochefort 10. Below
        // 6% its menu stops, so the wits and the fruit beers sit at £6.50 — the one figure here that's
        // reasoned rather than read. Retail is roughly £4 a bottle less, across the board.
        ("Leffe Blonde", .beer, 6.6, [(bottle330, 7)]),
        ("Leffe Brune", .beer, 6.5, [(bottle330, 7)]),
        ("Leffe Tripel", .beer, 8.5, [(bottle330, 7.4)]),
        ("Chimay Rouge", .beer, 7.0, [(bottle330, 7.1)]),
        ("Chimay Tripel", .beer, 8.0, [(bottle330, 7.5)]),
        ("Chimay Bleue", .beer, 9.0, [(bottle330, 7.8)]),
        ("Westmalle Dubbel", .beer, 7.0, [(bottle330, 7.1)]),
        ("Westmalle Tripel", .beer, 9.5, [(bottle330, 7.7)]),
        ("Rochefort 6", .beer, 7.5, [(bottle330, 7.3)]),
        ("Rochefort 8", .beer, 9.2, [(bottle330, 7.7)]),
        ("Rochefort 10", .beer, 11.3, [(bottle330, 8.9)]),
        ("Orval", .beer, 6.2, [(bottle330, 7)]),
        ("Duvel", .beer, 8.5, [(bottle330, 7.4)]),
        ("La Chouffe", .beer, 8.0, [(bottle330, 7.5)]),
        ("St Bernardus Abt 12", .beer, 10.0, [(bottle330, 8.5)]),
        ("St Bernardus Tripel", .beer, 8.0, [(bottle330, 7.5)]),
        ("St Bernardus Pater 6", .beer, 6.7, [(bottle330, 7)]),
        ("Gulden Draak", .beer, 10.5, [(bottle330, 8.5)]),
        ("Piraat", .beer, 10.5, [(bottle330, 8.5)]),
        ("Maredsous 8", .beer, 8.0, [(bottle330, 7.5)]),
        ("Maredsous 10", .beer, 10.0, [(bottle330, 8.5)]),
        ("Grimbergen Blonde", .beer, 6.7, [(bottle330, 7)]),
        ("Straffe Hendrik Tripel", .beer, 9.0, [(bottle330, 7.75)]),
        ("St Feuillien Blonde", .beer, 7.5, [(bottle330, 7.3)]),
        ("Tripel Karmeliet", .beer, 8.4, [(bottle330, 7.4)]),
        ("Delirium Tremens", .beer, 8.5, [(bottle330, 7.4)]),
        ("Delirium Nocturnum", .beer, 8.5, [(bottle330, 7.4)]),
        ("Pauwel Kwak", .beer, 8.4, [(bottle330, 7.4)]),
        ("Brugse Zot Blond", .beer, 6.0, [(bottle330, 7)]),
        ("Saison Dupont", .beer, 6.5, [(bottle330, 7)]),
        ("Rodenbach Grand Cru", .beer, 6.0, [(bottle330, 7)]),
        ("Duchesse de Bourgogne", .beer, 6.2, [(bottle330, 7)]),
        ("De Koninck", .beer, 5.2, [(bottle330, 6.5)]),
        ("Jupiler", .beer, 5.2, [(bottle330, 6.5)]),
        ("Vedett Extra Blond", .beer, 5.2, [(bottle330, 6.5)]),
        ("Blanche de Bruxelles", .beer, 4.5, [(bottle330, 6.5)]),
        ("Fruli", .beer, 4.1, [(bottle330, 6.5)]),
        // Bavarian, off the shelf. The half-litre bottle is the format; Ayinger comes in 330 here.
        ("Augustiner Helles", .beer, 5.2, [(bottle500, 3.39)]),
        ("Augustiner Edelstoff", .beer, 5.6, [(bottle500, 4.25)]),
        ("Spaten Münchner Hell", .beer, 5.2, [(bottle500, 3.83)]),
        ("Löwenbräu Original", .beer, 5.2, [(bottle500, 3.95)]),
        ("Tegernseer Hell", .beer, 4.8, [(bottle500, 4.2)]),
        ("Andechs Vollbier Hell", .beer, 4.8, [(bottle500, 4.2)]),
        ("Hofbräu Münchner Weisse", .beer, 5.1, [(bottle500, 3.85)]),
        ("Weihenstephaner Hefe Weissbier", .beer, 5.4, [(bottle500, 4.6)]),
        ("Weihenstephaner Korbinian", .beer, 7.4, [(bottle500, 4.55)]),
        ("Schneider Weisse Original", .beer, 5.4, [(bottle500, 3.25)]),
        ("Schneider Weisse Aventinus", .beer, 8.2, [(bottle500, 5.6)]),
        ("Franziskaner Hefe-Weissbier", .beer, 5.0, [(bottle500, 2.6)]),
        ("Maisel's Weisse", .beer, 5.1, [(bottle500, 2.66)]),
        ("König Ludwig Weissbier", .beer, 5.5, [(bottle500, 3.9)]),
        ("Paulaner Salvator", .beer, 7.9, [(bottle500, 4.69)]),
        ("Paulaner Oktoberfest Bier", .beer, 6.0, [(bottle500, 3.5)]),
        ("Erdinger Pikantus", .beer, 7.3, [(bottle500, 4)]),
        ("Ayinger Celebrator", .beer, 6.7, [(bottle330, 3.75)]),
        ("Ayinger Bräu-Weisse", .beer, 5.1, [(bottle500, 4.95)]),
        ("Hofbräu Original", .beer, 5.1, [(bottle500, 3.6)]),
        ("Weihenstephaner Vitus", .beer, 7.7, [(bottle500, 4.39)]),
        ("Weihenstephaner Kristall", .beer, 5.4, [(bottle500, 4.85)]),
        ("Hacker-Pschorr Münchner Gold", .beer, 5.5, [(bottle500, 2.75)]),
        ("Hacker-Pschorr Oktoberfest", .beer, 5.8, [(bottle500, 4.9)]),
        ("Schlenkerla Rauchbier Märzen", .beer, 5.1, [(bottle500, 3.9)]),
        // Stout
        ("Guinness", .stout, 4.2, [(pint, 6.7), (half, 3.4), (can440, 1.4)]),
        ("Guinness Extra Stout", .stout, 4.2, [(bottle500, 1.89)]),
        ("Murphy's", .stout, 4.0, [(pint, 6.5), (can440, 1.15)]),
        // Cider
        ("Thatchers Gold", .cider, 4.8, [(pint, 6.31), (can440, 1.31), (bottle500, 2.7)]),
        ("Thatchers Haze", .cider, 4.5, [(pint, 6.31), (bottle500, 2.6)]),
        ("Thatchers Blood Orange", .cider, 3.4, [(pint, 6.31), (bottle500, 2.35)]),
        ("Strongbow", .cider, 4.5, [(pint, 6), (can440, 1.75)]),
        ("Strongbow Dark Fruit", .cider, 4.0, [(pint, 6), (can440, 1.46)]),
        ("Bulmers Original", .cider, 4.5, [(pint, 6.15), (bottle500, 1.45)]),
        ("Magners", .cider, 4.5, [(pint, 6.15), (bottle568, 2.5), (can440, 1.19)]),
        ("Inch's", .cider, 4.5, [(pint, 5.6), (bottle500, 2.85)]),
        ("Aspall", .cider, 5.5, [(pint, 6.6), (bottle500, 2.9)]),
        ("Stowford Press", .cider, 4.5, [(pint, 4.4), (can568, 1.8)]),
        ("Cornish Orchards Gold", .cider, 5.0, [(pint, 6.4), (bottle500, 2.95)]),
        ("Henry Westons Vintage", .cider, 8.2, [(bottle500, 2.3)]),
        ("Westons Old Rosie", .cider, 6.8, [(pint, 6.2), (bottle500, 2.99)]),
        ("Kopparberg Strawberry & Lime", .cider, 4.0, [(bottle500, 2.19)]),
        ("Kopparberg Mixed Fruit", .cider, 4.0, [(bottle500, 2.34)]),
        ("Rekorderlig Strawberry & Lime", .cider, 4.0, [(bottle500, 2.6)]),
        ("Old Mout Kiwi & Lime", .cider, 4.0, [(bottle500, 2.4)]),
        // Super-strength — the corner-shop singles. Most were cut to 7.5% in the mid-2010s, years before
        // the 2023 duty reform set its higher rate at 8.5%; Kestrel and Karpackie Super Mocne are the
        // holdouts still brewed above the cliff and paying for it. Special Brew is two beers: the 500 ml
        // single is 7.5%, the supermarket 4×440 is 8%, and only the single is priced here. Tennent's
        // Super and Skol Super are the pack rate — nowhere indexes what a shop charges for one can.
        ("Carlsberg Special Brew", .beer, 7.5, [(can500, 3.38)]),
        ("Tennent's Super", .beer, 7.5, [(can500, 2.75)]),
        ("Skol Super", .beer, 8.0, [(can500, 2)]),
        ("Kestrel Super Premium", .beer, 9.0, [(can500, 3.33)]),
        ("Karpackie Super Mocne", .beer, 9.0, [(can500, 2.71)]),
        ("K Cider", .cider, 7.5, [(can500, 2.25)]),
        ("Ace Cider", .cider, 7.5, [(can500, 1.29)]),
        // White cider is sold by the 2.5 litre bottle, which is 18 units — the pint is what gets poured.
        ("Frosty Jack's", .cider, 7.5, [(pint, 1.47), (bottle2500, 6.49)]),
        ("Omega White", .cider, 7.5, [(pint, 1.14), (bottle2500, 5)]),
        // Fizz
        ("Prosecco", .bubbles, 11.0, [(flute, 9), (wineBottle, 8.5)]),
        ("Champagne", .bubbles, 12.0, [(flute, 10.2), (wineBottle, 26)]),
        ("Cava", .bubbles, 11.5, [(flute, 6), (wineBottle, 5.99)]),
        ("Crémant", .bubbles, 12.0, [(flute, 9.5), (wineBottle, 13.5)]),
        ("English sparkling", .bubbles, 12.0, [(flute, 12.75), (wineBottle, 30)]),
        ("Lambrusco", .bubbles, 8.0, [(flute, 8.5), (wineBottle, 3.25)]),
        ("Asti", .bubbles, 7.5, [(flute, 8.5), (wineBottle, 8.75)]),
        ("Lambrini", .bubbles, 6.0, [(flute, 0.5), (wineBottle, 2.99)]),
        // Champagne worth the name
        ("Moët & Chandon Impérial", .bubbles, 12.0, [(flute, 19.5), (wineBottle, 45)]),
        ("Veuve Clicquot Yellow Label", .bubbles, 12.0, [(flute, 20), (wineBottle, 55)]),
        ("Bollinger Special Cuvée", .bubbles, 12.0, [(flute, 15), (wineBottle, 60)]),
        ("Laurent-Perrier Cuvée Rosé", .bubbles, 12.0, [(flute, 30), (wineBottle, 82)]),
        ("Taittinger Brut Réserve", .bubbles, 12.5, [(flute, 22), (wineBottle, 46)]),
        ("Pol Roger Brut Réserve", .bubbles, 12.5, [(flute, 18.75), (wineBottle, 45)]),
        ("Dom Pérignon 2015", .bubbles, 12.5, [(flute, 65), (wineBottle, 210)]),
        ("Krug Grande Cuvée 172ème Édition", .bubbles, 12.5, [(flute, 43.83), (wineBottle, 263)]),
        ("Louis Roederer Cristal 2016", .bubbles, 12.0, [(flute, 48.33), (wineBottle, 290)]),
        ("Armand de Brignac Brut Gold", .bubbles, 12.5, [(flute, 42.75), (wineBottle, 256.49)]),
        // Bottles you'd open for something, priced by the vintage named: strength and price both move
        // year to year, so an unvintaged name would be two different wines wearing one price. Where
        // nowhere in London pours one by the glass, the glass is a sixth of the bottle.
        // Once in a lifetime. Strengths come from auction listings, except the 1841, which was measured:
        // the bottles salvaged off Åland had fermented cool and slow and came out at 9%.
        ("Dom Pérignon P3 1971", .bubbles, 12.5, [(flute, 6270), (wineBottle, 37620)]),
        ("Veuve Clicquot 1841 (Åland wreck)", .bubbles, 9.0, [(flute, 4450), (wineBottle, 26700)]),
        // White
        ("Pinot Grigio", .whiteWine, 12.0, [(glass175, 6.7), (glass250, 9.1), (wineBottle, 8.25)]),
        ("Sauvignon Blanc", .whiteWine, 12.5, [(glass175, 7.4), (glass250, 10.05), (wineBottle, 9.75)]),
        ("Chardonnay", .whiteWine, 13.0, [(glass175, 7), (glass250, 9.45), (wineBottle, 9.5)]),
        ("Chablis", .whiteWine, 12.5, [(glass175, 9.5), (wineBottle, 16)]),
        ("Picpoul de Pinet", .whiteWine, 12.5, [(glass175, 11.5), (wineBottle, 10)]),
        ("Albariño", .whiteWine, 12.5, [(glass175, 8.5), (wineBottle, 12)]),
        ("Riesling", .whiteWine, 11.5, [(glass175, 7), (glass250, 9.45), (wineBottle, 8.5)]),
        ("Chenin Blanc", .whiteWine, 12.5, [(glass175, 7), (glass250, 9.45), (wineBottle, 8.75)]),
        ("Gavi", .whiteWine, 12.0, [(glass175, 9.5), (wineBottle, 10)]),
        ("Vinho Verde", .whiteWine, 10.5, [(glass175, 7), (wineBottle, 7)]),
        ("Viognier", .whiteWine, 13.0, [(glass175, 7), (wineBottle, 9)]),
        ("Cloudy Bay 2025", .whiteWine, 13.0, [(glass175, 15), (wineBottle, 27.95)]),
        ("Puligny-Montrachet 2023", .whiteWine, 13.0, [(glass125, 14.99), (wineBottle, 89.95)]),
        ("Château d'Yquem 1811", .whiteWine, 13.6, [(glass125, 12500), (wineBottle, 75000)]),
        // Red
        ("Rioja", .redWine, 13.5, [(glass175, 5.35), (glass250, 7.2), (wineBottle, 9.25)]),
        ("Malbec", .redWine, 13.5, [(glass175, 7.2), (glass250, 9.75), (wineBottle, 9.5)]),
        ("Merlot", .redWine, 13.5, [(glass175, 7), (glass250, 9.45), (wineBottle, 6.5)]),
        ("Shiraz", .redWine, 14.0, [(glass175, 8.6), (glass250, 11.75), (wineBottle, 8.75)]),
        ("Pinot Noir", .redWine, 13.0, [(glass175, 6.7), (glass250, 9.05), (wineBottle, 11.5)]),
        ("Cabernet Sauvignon", .redWine, 13.5, [(glass175, 7), (glass250, 9.45), (wineBottle, 7.75)]),
        ("Chianti", .redWine, 13.0, [(glass175, 11.1), (glass250, 15), (wineBottle, 12)]),
        ("Côtes du Rhône", .redWine, 14.0, [(glass175, 7), (wineBottle, 9)]),
        ("Primitivo", .redWine, 13.5, [(glass175, 7), (glass250, 9.45), (wineBottle, 8.75)]),
        ("Zinfandel", .redWine, 14.5, [(glass175, 7), (wineBottle, 8.75)]),
        ("Beaujolais", .redWine, 12.5, [(glass175, 7), (wineBottle, 9)]),
        ("Carménère", .redWine, 13.5, [(glass175, 7), (wineBottle, 9)]),
        ("Tignanello 2022", .redWine, 14.0, [(glass125, 29.17), (wineBottle, 175)]),
        ("Sassicaia 2022", .redWine, 13.5, [(glass125, 49.99), (wineBottle, 299.95)]),
        ("Opus One 2021", .redWine, 14.5, [(glass125, 49.99), (wineBottle, 299.95)]),
        ("Château Lafite Rothschild 2025", .redWine, 12.5, [(glass125, 57.83), (wineBottle, 347)]),
        ("Château Margaux 2020", .redWine, 13.5, [(glass125, 72.17), (wineBottle, 433)]),
        ("Penfolds Grange 2019", .redWine, 14.5, [(glass125, 83.33), (wineBottle, 500)]),
        ("Château Pétrus 2016", .redWine, 14.9, [(glass125, 438.83), (wineBottle, 2633)]),
        ("Domaine de la Romanée-Conti 2023", .redWine, 14.0, [(glass125, 747.5), (wineBottle, 4485)]),
        ("Château Mouton Rothschild 1945", .redWine, 15.0, [(glass125, 5416.67), (wineBottle, 32500)]),
        ("Penfolds Grange 1951", .redWine, 12.3, [(glass125, 14125), (wineBottle, 84750)]),
        ("Screaming Eagle 1992", .redWine, 13.0, [(glass125, 1708.33), (wineBottle, 10250)]),
        // Rosé
        ("Provence rosé", .rose, 12.5, [(glass175, 9.5), (glass250, 12.8), (wineBottle, 10)]),
        ("Pinot Grigio rosé", .rose, 12.0, [(glass175, 7), (glass250, 9.45), (wineBottle, 8.25)]),
        ("White Zinfandel", .rose, 10.5, [(glass175, 7), (glass250, 9.45), (wineBottle, 6.25)]),
        // Port, sherry & vermouth
        ("Port", .fortified, 20.0, [(port, 3.5)]),
        ("Madeira", .fortified, 19.0, [(port, 3.5)]),
        ("Sherry", .fortified, 15.0, [(schooner, 4.9)]),
        ("Cream sherry", .fortified, 17.5, [(schooner, 5.2)]),
        ("Vermouth", .fortified, 15.0, [(port, 3.5), (schooner, 4.9)]),
        ("Buckfast", .fortified, 15.0, [(glass175, 3.03), (halfBottle, 5.5), (wineBottle, 12.99)]),
        // Tonic wine and the cheap fortified end, priced by the bottle with the glass pro-rata.
        // MD 20/20 is 13% in every UK flavour; the 13-18% range you'll read is the American line.
        ("MD 20/20", .fortified, 13.0, [(glass175, 2.28), (wineBottle, 9.79)]),
        ("Sanatogen Tonic Wine", .fortified, 15.0, [(glass175, 1.25), (bottle70cl, 4.99)]),
        ("QC Sherry", .fortified, 17.5, [(schooner, 0.9), (bottle70cl, 8.99)]),
        ("Emva Cream", .fortified, 15.0, [(schooner, 0.65), (bottle70cl, 6.49)]),
        ("Harveys Bristol Cream", .fortified, 17.5, [(schooner, 0.88), (wineBottle, 9.38)]),
        ("Stone's Green Ginger Wine", .fortified, 13.5, [(port, 0.57), (bottle70cl, 7.99)]),
        ("Crabbie's Green Ginger Wine", .fortified, 13.5, [(port, 0.51), (bottle70cl, 7.15)]),
        // Gin
        ("Gordon's Gin", .spirit, 37.5, [(single, 6.8), (single35, 9.5), (bottle70cl, 19.5)]),
        ("Gordon's Pink", .spirit, 37.5, [(single, 6.8), (single35, 9.5), (bottle70cl, 27)]),
        ("Tanqueray", .spirit, 41.3, [(single, 6.8), (single35, 9.5), (bottle70cl, 23)]),
        ("Bombay Sapphire", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 24.25)]),
        ("Hendrick's", .spirit, 41.4, [(single, 7.4), (single35, 10.35), (bottle70cl, 26)]),
        ("Beefeater", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 18)]),
        ("Whitley Neill Rhubarb & Ginger", .spirit, 43.0, [(single, 7.4), (single35, 10.35), (bottle70cl, 30)]),
        // Vodka
        ("Smirnoff", .spirit, 37.5, [(single, 6.8), (single35, 9.5), (bottle70cl, 16)]),
        ("Absolut", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 23)]),
        ("Grey Goose", .spirit, 40.0, [(single, 7.7), (single35, 10.8), (bottle70cl, 39.5)]),
        // Whisky
        ("Jack Daniel's", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 24.5)]),
        ("Jameson", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 26.5)]),
        ("The Famous Grouse", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 18.5)]),
        ("Bell's", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 19.5)]),
        ("Johnnie Walker Black Label", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 36)]),
        ("Monkey Shoulder", .spirit, 40.0, [(single, 7.4), (single35, 10.35), (bottle70cl, 31)]),
        ("Glenfiddich 12", .spirit, 40.0, [(single, 7.25), (single35, 10.15), (bottle70cl, 42.5)]),
        ("Glenmorangie", .spirit, 40.0, [(single, 7.25), (single35, 10.15), (bottle70cl, 41)]),
        ("Laphroaig 10", .spirit, 40.0, [(single, 7.5), (single35, 10.5), (bottle70cl, 42)]),
        ("Jim Beam", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 21.5)]),
        ("Maker's Mark", .spirit, 45.0, [(single, 7.4), (single35, 10.35), (bottle70cl, 35)]),
        ("Bulleit Bourbon", .spirit, 45.0, [(single, 7.4), (single35, 10.35), (bottle70cl, 20)]),
        // Rum & tequila
        ("Bacardi", .spirit, 37.5, [(single, 6.8), (single35, 9.5), (bottle70cl, 19)]),
        ("Captain Morgan Spiced", .spirit, 35.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 27)]),
        ("The Kraken", .spirit, 40.0, [(single, 7.4), (single35, 10.35), (bottle70cl, 26.5)]),
        ("Havana Club 3", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 21)]),
        ("Appleton Estate Signature", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 25.95)]),
        ("Lamb's Navy Rum", .spirit, 40.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 19.5)]),
        ("Koko Kanu", .spirit, 37.5, [(single, 6.8), (single35, 9.5), (bottle70cl, 21.5)]),
        // Overproof. A 25 ml single of Wray & Nephew carries three times the alcohol of one of Malibu,
        // which is the whole reason to log it as itself rather than as "rum". The two nobody pours by
        // the measure are bottle-only; a shot from your own bottle prices pro-rata.
        ("Wray & Nephew White Overproof", .spirit, 63.0, [(single, 7.4), (single35, 10.35), (bottle70cl, 27)]),
        ("Wood's Old Navy Rum", .spirit, 57.0, [(single, 7.4), (single35, 10.35), (bottle70cl, 29.95)]),
        ("Pusser's Gunpowder Proof", .spirit, 54.5, [(single, 7.4), (single35, 10.35), (bottle70cl, 39.5)]),
        ("Rum Fire", .spirit, 63.0, [(bottle70cl, 49.99)]),
        ("Sunset Very Strong Rum", .spirit, 84.5, [(bottle70cl, 48.65)]),
        ("Malibu", .spirit, 18.0, [(single, 6.8), (single35, 9.5), (bottle70cl, 12.5)]),
        ("Tequila", .spirit, 38.0, [(single, 6.8), (single35, 9.5)]),
        // Liqueurs & aperitifs
        ("Baileys", .spirit, 17.0, [(port, 7.4)]),
        ("Jägermeister", .spirit, 35.0, [(single, 6.8)]),
        ("Disaronno", .spirit, 28.0, [(single, 7.4), (single35, 10.35)]),
        ("Cointreau", .spirit, 40.0, [(single, 7.4), (single35, 10.35)]),
        ("Southern Comfort", .spirit, 35.0, [(single, 6.8), (single35, 9.5)]),
        ("Tia Maria", .spirit, 20.0, [(single, 6.8), (single35, 9.5)]),
        ("Archers", .spirit, 18.0, [(single, 6.8), (single35, 9.5)]),
        ("Sambuca", .spirit, 38.0, [(single, 6.8)]),
        ("Fireball", .spirit, 33.0, [(single, 6.8)]),
        ("Courvoisier VS", .spirit, 40.0, [(single, 8.5), (single35, 11.9)]),
        ("Hennessy VS", .spirit, 40.0, [(single, 8.5), (single35, 11.9)]),
        ("Pimm's No. 1", .spirit, 22.0, [(single35, 6), (bottle70cl, 13.5)]),
        ("Aperol", .spirit, 11.0, [(single35, 5.5), (bottle70cl, 23.5)]),
        ("Campari", .spirit, 25.0, [(single, 7.4), (single35, 10.35)]),
        // Spirit & mixer, as poured
        ("Gin & tonic", .cocktail, 4.2, [(longDrink, 6.5)]),
        ("Double gin & tonic", .cocktail, 7.5, [(doubleLong, 9.6)]),
        ("Vodka & mixer", .cocktail, 4.2, [(longDrink, 6.5)]),
        ("Double vodka & mixer", .cocktail, 7.5, [(doubleLong, 9.6)]),
        ("Rum & Coke", .cocktail, 4.2, [(longDrink, 6.5)]),
        ("Double rum & Coke", .cocktail, 7.5, [(doubleLong, 9.6)]),
        ("Whisky & Coke", .cocktail, 4.2, [(longDrink, 6.5)]),
        ("Vodka Red Bull", .cocktail, 4.0, [(doubleLong, 11.1)]),
        ("Jägerbomb", .cocktail, 3.2, [(doubleLong, 7.3)]),
        ("Pimm's & lemonade", .cocktail, 5.0, [(doubleLong, 7)]),
        // Cocktails
        ("Aperol Spritz", .cocktail, 8.0, [(.init(.wineGlass, 200), 11.5)]),
        ("Espresso Martini", .cocktail, 15.0, [(smallCoupe, 11.95)]),
        ("Margarita", .cocktail, 16.0, [(coupe, 11.95)]),
        ("Mojito", .cocktail, 8.0, [(doubleLong, 11.5)]),
        ("Negroni", .cocktail, 24.0, [(rocks, 10.5)]),
        ("Old Fashioned", .cocktail, 32.0, [(.init(.tumbler, 70), 12.95)]),
        ("Cosmopolitan", .cocktail, 18.0, [(smallCoupe, 11.5)]),
        ("Porn Star Martini", .cocktail, 14.0, [(coupe, 12.5)]),
        ("Daiquiri", .cocktail, 20.0, [(smallCoupe, 11.5)]),
        ("Piña Colada", .cocktail, 8.0, [(doubleLong, 11.5)]),
        ("Long Island Iced Tea", .cocktail, 10.0, [(doubleLong, 11.95)]),
        ("Bloody Mary", .cocktail, 8.0, [(doubleLong, 7)]),
        ("Sangria", .cocktail, 9.0, [(glass250, 9)]),
        ("Buck's Fizz", .cocktail, 6.0, [(flute, 9)]),
        // Ready-to-drink
        ("Gordon's G&T can", .alcopop, 5.0, [(can250, 2.19)]),
        ("Gordon's Pink G&T can", .alcopop, 5.0, [(can250, 1.99)]),
        ("Bacardi & Cola can", .alcopop, 5.0, [(can250, 2.17)]),
        ("Captain Morgan & Cola can", .alcopop, 5.0, [(can250, 2.19)]),
        ("Jack Daniel's & Cola can", .alcopop, 5.0, [(can330, 2.43)]),
        ("White Claw", .alcopop, 4.5, [(can330, 2.4)]),
        ("WKD", .alcopop, 4.0, [(bottle275, 2.01)]),
        ("VK", .alcopop, 4.0, [(bottle275, 2)]),
        ("Smirnoff Ice", .alcopop, 4.0, [(bottle275, 2.01)]),
        ("Hooch", .alcopop, 4.0, [(bottle440, 2.1)]),
    ]

    static let brands: [CatalogBrand] = entries.map { CatalogBrand(name: $0.0, category: $0.1, abv: $0.2, serves: $0.3) }

    static let items: [CatalogItem] = brands.flatMap { brand in
        brand.serves.map { CatalogItem(name: brand.name, category: brand.category, vessel: $0.size.vessel, volumeMl: $0.size.ml, abv: brand.abv, price: $0.price) }
    }

    /// What a brand costs in a size it may not be listed in — its own price for that size, else the
    /// first serve scaled by volume, the same way a drink's own price scales.
    /// Whether a drink is still exactly as the catalogue has it — copied in when it was logged and never touched.
    /// Change its name, kind or strength and it stops matching, which is the point: it's yours from then on.
    static func holds(name: String, category: DrinkCategory, abv: Double) -> Bool {
        brands.contains { $0.name == name && $0.category == category && $0.abv == abv }
    }

    /// What a drink of this name in this size normally costs: a brand's own price, else a generic's starting one.
    /// Nil where nothing is known, so a caller can tell "we don't price this" from "this is free".
    static func price(name: String, category: DrinkCategory, vessel: Vessel, ml: Double) -> Double? {
        if let brand = brands.first(where: { $0.name == name && $0.category == category }) {
            let found = price(brand, vessel, ml)
            return found > 0 ? found : nil
        }
        return Seed.price(name: name, vessel: vessel, ml: ml)
    }

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
