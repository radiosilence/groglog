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
    /// Craft therefore splits two ways, and it looks wrong until you know why: the breweries a
    /// supermarket stocks carry the four-pack rate, and the ones only a bottle shop sells carry what
    /// it charges for one. A Camden Hells really is a third of a Verdant, because of where you buy it.
    /// Craft pints are the tier too, banded by strength off the ones pubs do publish — Camden Pale at
    /// £6.30, Hepcat and Gamma Ray at £6.90, Camden Hells and Punk IPA at £7.05, Elvis Juice at £7.50.
    /// Your pub will differ by a pound either way; it's a starting price, and the drink becomes yours.
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
    private static let bottle2000 = ServeSize(.bottle, 2000)
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
    private static let bottle1l = ServeSize(.wineBottle, 1000)
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
        ("Okocim Jasne", .beer, 5.2, [(can500, 2.04)]),
        ("Okocim Mocne", .beer, 6.5, [(can500, 1.99)]),
        ("Warka Classic", .beer, 5.2, [(can500, 1.99)]),
        ("Warka Strong", .beer, 6.5, [(can500, 2.19)]),
        ("Perła Chmielowa", .beer, 6.0, [(bottle500, 2.1)]),
        ("Perła Mocna", .beer, 7.1, [(can500, 1.89)]),
        ("Łomża Export", .beer, 5.7, [(can500, 1.99)]),
        ("Harnaś", .beer, 5.9, [(can500, 1.99)]),
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
        ("Velkopopovický Kozel Černý", .beer, 3.8, [(can500, 2.25)]),
        ("Krušovice Original", .beer, 4.2, [(can500, 2.56)]),
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
        ("Ciucaș", .beer, 4.6, [(bottle330, 1.79), (can500, 2.5)]),
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
        // Gipsy Hill. Bandit is 3.4% on the brewery's own page and 3.8% at two shops; 3.4% is the duty
        // band breweries deliberately brew down to, so it's the likelier current recipe. HepcAF is the
        // alcohol-free one and isn't here — Trail, despite the eco-branding, is a full-strength pale.
        ("Gipsy Hill Hepcat", .beer, 4.6, [(pint, 6.9), (can330, 2.95)]),
        ("Gipsy Hill Swell", .beer, 4.0, [(pint, 6.6), (can330, 2.65)]),
        ("Gipsy Hill Bandit", .beer, 3.4, [(pint, 6.6), (can330, 2.8)]),
        ("Gipsy Hill Trail", .beer, 4.0, [(pint, 6.6), (can330, 2.7)]),
        ("Gipsy Hill Apogee", .stout, 4.0, [(can440, 4)]),
        ("Gipsy Hill Freewheeler", .beer, 6.0, [(can440, 4.5)]),
        ("Gipsy Hill Quaint Towns", .beer, 6.8, [(can440, 4.65)]),
        ("Gipsy Hill Waidmanns", .beer, 5.8, [(can440, 4)]),
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
        ("Meantime Greenwich Lager", .beer, 4.5, [(pint, 6.95), (bottle330, 1.58)]),
        ("Meantime Prime Pale", .beer, 4.3, [(pint, 6.6), (can330, 1.63)]),
        ("Meantime Yakima Red", .beer, 4.5, [(pint, 6.95), (can440, 2)]),
        ("Meantime Anytime IPA", .beer, 4.7, [(pint, 6.95), (bottle330, 1.58)]),
        ("Camden Off Menu IPA", .beer, 5.8, [(pint, 6.75), (can330, 1.8)]),
        ("Camden Stout", .stout, 4.0, [(pint, 6.6), (can440, 1.63)]),
        ("Camden Week Nite", .beer, 3.0, [(pint, 6.6), (can330, 2.15)]),
        ("Wolfpack Lager", .beer, 5.0, [(pint, 5.2)]),
        ("Wolfpack Pilsner", .beer, 4.4, [(pint, 5)]),
        ("Brixton Reliance Pale Ale", .beer, 4.2, [(pint, 6.6), (can330, 1.5)]),
        ("Brixton Coldharbour Lager", .beer, 4.4, [(pint, 6.6), (can330, 1.18)]),
        ("Brixton Atlantic", .beer, 5.4, [(pint, 6.95), (can330, 2.5)]),
        ("Brixton Livewire", .beer, 6.0, [(pint, 7.2), (can330, 2.58)]),
        ("Brixton Low Voltage", .beer, 4.3, [(pint, 6.6), (can330, 2.42)]),
        ("Brixton Rewired", .beer, 3.4, [(pint, 6.6), (can330, 2.6)]),
        ("Sambrook's Wandle", .beer, 3.8, [(pint, 6.6), (bottle500, 3)]),
        ("Sambrook's Pumphouse", .beer, 4.2, [(pint, 6.6), (bottle500, 3)]),
        ("Sambrook's Junction", .beer, 4.5, [(pint, 6.95), (bottle500, 3)]),
        ("Mondo Little Victories", .beer, 4.3, [(pint, 6.6), (can330, 2.21)]),
        ("Mondo Dennis Hopp'r", .beer, 5.3, [(pint, 6.95), (can330, 2.52)]),
        ("Mondo Road Soda", .beer, 4.8, [(pint, 6.95), (can330, 2.34)]),
        ("Mondo Navigator", .stout, 4.0, [(pint, 6.6), (can330, 2.38)]),
        ("Mondo Texas Whistle", .beer, 4.4, [(pint, 6.6), (can330, 2.03)]),
        ("Belleville Rock Lobster", .beer, 4.8, [(pint, 6.95), (can440, 4)]),
        ("Belleville Patriot", .beer, 4.1, [(pint, 6.6), (can440, 3.75)]),
        ("Belleville Savannah Sour", .beer, 4.4, [(can440, 2.6)]),
        ("Belleville London Steam Lager", .beer, 4.5, [(pint, 6.95), (can330, 2.4)]),
        ("Belleville Picnic Session IPA", .beer, 4.4, [(pint, 6.6), (can330, 2.6)]),
        ("Belleville Commonside Pale Ale", .beer, 4.8, [(pint, 6.95), (can330, 2.6)]),
        ("Belleville Thames Surf IPA", .beer, 5.6, [(pint, 7.2), (can330, 2.8)]),
        ("Belleville The Breeze", .beer, 2.4, [(pint, 6.6), (can330, 2.2)]),
        // Big Smoke sell by the six and nothing smaller, so the can is that case's rate.
        ("Big Smoke Cold Spark", .beer, 3.4, [(pint, 6.6), (can330, 2.08)]),
        ("Big Smoke Pilsner", .beer, 4.0, [(pint, 6.6), (can330, 2.08)]),
        ("Big Smoke Universal", .beer, 4.3, [(pint, 6.6), (can330, 2.08)]),
        ("Big Smoke Helles Lager", .beer, 4.7, [(pint, 6.95), (can330, 2.08)]),
        ("Big Smoke Electric Eye", .beer, 5.0, [(pint, 6.95), (can330, 2.08)]),
        ("Big Smoke Medicine Man", .beer, 6.0, [(pint, 7.2), (can330, 2.08)]),
        ("Wimbledon Lager", .beer, 4.8, [(pint, 6.95), (can330, 2.21)]),
        ("Wimbledon Pale", .beer, 4.2, [(pint, 6.6), (can330, 2.15)]),
        ("Two Tribes Campfire", .beer, 5.2, [(pint, 6.95), (can330, 2.35)]),
        ("Two Tribes Dream", .beer, 4.4, [(pint, 6.6), (can330, 2.5)]),
        ("Two Tribes Super Deluxe", .beer, 4.0, [(pint, 6.6), (can330, 2.5)]),
        ("Forest Road Posh", .beer, 4.1, [(pint, 6.6), (can330, 2.95)]),
        ("Forest Road Work", .beer, 5.4, [(pint, 6.95), (can330, 2.95)]),
        ("Forest Road Ride", .beer, 4.6, [(pint, 6.95), (can330, 2.95)]),
        ("Toast Grassroots Pale Ale", .beer, 4.1, [(can330, 3.29)]),
        ("Toast Rise Up Lager", .beer, 4.6, [(can330, 2.08)]),
        ("Toast New Dawn", .beer, 4.3, [(can330, 2.08)]),
        ("Jubel", .beer, 4.0, [(pint, 5), (can330, 2.4), (can440, 3.05)]),
        ("Hiver Blonde", .beer, 4.5, [(bottle330, 1.5)]),
        ("Hiver Amber", .beer, 4.5, [(bottle330, 1.5)]),
        ("Anspach & Hobday The London Black", .beer, 4.4, [(pint, 6.6), (can440, 4.6)]),
        ("Anspach & Hobday Table Beer", .beer, 2.7, [(pint, 6.6), (can440, 2.95)]),
        ("Anspach & Hobday The IPA", .beer, 6.0, [(pint, 7.2), (can440, 4.05)]),
        ("Anspach & Hobday Bermondsey Pale Ale", .beer, 3.4, [(pint, 6.6), (can440, 3.35)]),
        ("Anspach & Hobday Ansbacher Lager", .beer, 5.0, [(pint, 6.95), (can440, 3.45)]),
        ("Anspach & Hobday The Porter", .beer, 6.7, [(pint, 7.6), (can440, 5)]),
        ("Anspach & Hobday Ordinary Bitter", .beer, 3.4, [(pint, 6.6), (can440, 3.05)]),
        // The Kernel brew to a style, not to a number: the hop changes batch to batch and the strength
        // with it, so these are the current figure rather than a fixed one. Edit yours to what the can says.
        ("Kernel Table Beer", .beer, 3.0, [(pint, 6.6), (can330, 3.25)]),
        ("Kernel Pale Ale", .beer, 5.3, [(pint, 6.95), (can330, 3.75)]),
        ("Kernel India Pale Ale", .beer, 7.0, [(pint, 7.6), (can330, 4.5)]),
        ("Kernel Dry Stout", .stout, 4.7, [(pint, 6.95), (can330, 3.65)]),
        ("Kernel Export Stout", .stout, 7.5, [(pint, 7.6), (can330, 4.7)]),
        ("Kernel Bière de Saison", .beer, 4.9, [(pint, 6.95), (can330, 4.8)]),
        ("Drop Project Shifty", .beer, 5.2, [(pint, 6.95), (can440, 4)]),
        ("Drop Project Glisten", .beer, 5.8, [(pint, 7.2), (can440, 3.85)]),
        ("Drop Project Savage", .beer, 4.8, [(pint, 6.95), (can440, 3.4)]),
        ("Drop Project Choppy", .stout, 4.8, [(pint, 6.95), (can440, 3.4)]),
        ("Drop Project Strike", .beer, 4.2, [(pint, 6.6), (can440, 3.5)]),
        ("Drop Project Flow", .beer, 5.2, [(pint, 6.95), (can440, 4.85)]),
        ("Drop Project Crush", .beer, 4.2, [(pint, 6.6), (can440, 4)]),
        ("Bianca Road Easy", .beer, 4.1, [(pint, 6.6), (can440, 4.25)]),
        ("Bianca Road Crispy", .beer, 4.8, [(pint, 6.95), (can440, 4.25)]),
        ("Bianca Road Hazy", .beer, 5.0, [(pint, 6.95), (can440, 5)]),
        ("Bianca Road Juicy", .beer, 6.0, [(pint, 7.2), (can440, 6)]),
        // Partizan is still brewed, but in Leicestershire — the Bermondsey company went into liquidation
        // and the brand went with its founder to Langton.
        ("Partizan Pale Ale", .beer, 4.5, [(bottle330, 2.85)]),
        // Small Beer brew deliberately weak, which is the point of them and not a mistake in the numbers.
        ("Small Beer Lager", .beer, 2.1, [(can330, 2.5)]),
        ("Small Beer IPA", .beer, 2.3, [(can330, 2.5)]),
        ("Small Beer Pale", .beer, 2.5, [(can330, 2.5)]),
        ("Small Beer Hazy", .beer, 2.6, [(can330, 2.5)]),
        ("Five Points Pale", .beer, 4.4, [(pint, 4)]),
        ("Five Points XPA", .beer, 4.0, [(pint, 6.6), (can330, 2.99)]),
        ("Five Points Railway Porter", .beer, 4.8, [(pint, 6.95), (can330, 2.95)]),
        ("Signature Brew Studio Lager", .beer, 4.0, [(pint, 6.6), (can330, 1.58)]),
        ("Signature Brew Backstage IPA", .beer, 5.6, [(pint, 7.2), (can330, 2.67)]),
        ("Beavertown Bloody 'Ell", .beer, 5.5, [(pint, 7.2), (can330, 2.75)]),
        // Nanobot is Beavertown's low-alcohol one, but 2.8% is still drink — it's the 0.3% Lazer Crush
        // that stays out.
        ("Beavertown Nanobot", .beer, 2.8, [(can330, 2.2)]),
        ("Crate Lager", .beer, 4.8, [(pint, 6.95), (can330, 2.08)]),
        ("Hackney Church Exodus", .beer, 5.5, [(pint, 7.2), (can440, 4.75)]),
        ("Hackney Church Renaissance", .beer, 4.5, [(pint, 6.95), (can440, 3.5)]),
        ("Hackney Church St Clements", .beer, 5.0, [(pint, 6.95), (can440, 3.5)]),
        ("Hackney Church Halo", .beer, 5.1, [(pint, 6.95), (can440, 3.5)]),
        ("Hackney Church Superfly", .beer, 6.0, [(pint, 7.2), (can440, 4.25)]),
        ("40FT Disco Pils", .beer, 4.0, [(pint, 6.6), (can330, 1.75)]),
        ("Wild Card IPA", .beer, 5.5, [(pint, 7.2), (can330, 3.2)]),
        ("Wild Card Pale Ale", .beer, 4.3, [(pint, 6.6), (can330, 3.1)]),
        ("Villages Rodeo", .beer, 4.6, [(pint, 4), (can330, 2.8)]),
        ("Villages Rafiki", .beer, 4.3, [(pint, 6.6), (can330, 3.2)]),
        ("Orbit Peel", .beer, 4.9, [(pint, 6.95), (bottle330, 2.63)]),
        ("Orbit Nico", .beer, 4.8, [(pint, 6.95), (bottle330, 2.63)]),
        ("Orbit Ivo", .beer, 4.2, [(pint, 6.6), (bottle330, 2.63)]),
        ("Orbit Dead Wax", .beer, 5.5, [(pint, 7.2), (bottle330, 2.63)]),
        // Hammerton's own shop is cheaper by the four-pack; these are what a bottle shop charges for one.
        ("Hammerton Panama Creature", .beer, 4.3, [(pint, 6.6), (can330, 3)]),
        ("Hammerton TUNED", .beer, 4.1, [(pint, 6.6), (can330, 3)]),
        ("Hammerton GROLL", .beer, 4.7, [(pint, 6.95), (can330, 3)]),
        ("Hammerton CRUNCH", .stout, 5.3, [(pint, 6.95), (can330, 3.7)]),
        ("Bohem Amos", .beer, 4.9, [(pint, 6.95), (can440, 4.1)]),
        ("Pressure Drop Pale Fire", .beer, 4.8, [(pint, 6.95), (can440, 3.85)]),
        ("Howling Hops Tropical Deluxe", .beer, 3.8, [(pint, 5.9), (can440, 3.2)]),
        ("Howling Hops Barley Pop", .beer, 4.4, [(pint, 6.6), (can440, 3.1)]),
        // Deya's core range, at what the brewery itself charges. A shop wants half as much again.
        ("Deya Steady Rolling Man", .beer, 5.2, [(half, 3), (can500, 4.5)]),
        ("Deya Into The Haze", .beer, 6.2, [(pint, 7.2), (can500, 5.5)]),
        ("Deya Boost", .beer, 4.0, [(pint, 6.6), (can500, 4.2)]),
        ("Deya Magazine Cover", .beer, 4.2, [(pint, 6.6), (can500, 4.2)]),
        ("Deya Tappy Pils", .beer, 4.4, [(pint, 6.6), (can500, 3.8)]),
        // Brockley, whose shop is down to four beers since brewing moved off Harcourt Road in 2024 —
        // the porter, the bitter and the rest are off it. Sold in sixes, so the can is the pack's rate.
        ("Brockley Pale Ale", .beer, 4.1, [(pint, 6.6), (can330, 2.67)]),
        ("Brockley Lager", .beer, 4.1, [(pint, 6.6), (can330, 2.67)]),
        ("Brockley Session IPA", .beer, 4.4, [(pint, 6.6), (can330, 2.67)]),
        ("Brockley Hilly Fields IPA", .beer, 5.7, [(pint, 7.2), (can330, 3)]),
        ("Cloudwater DDH Pale", .beer, 5.0, [(pint, 6.95), (can440, 4.75)]),
        ("Northern Monk Faith", .beer, 5.0, [(pint, 6.95), (can440, 3)]),
        ("Northern Monk Heathen", .beer, 7.2, [(pint, 7.6), (can440, 3.75)]),
        ("Verdant Headband", .beer, 5.5, [(pint, 7.2), (can440, 4.8)]),
        ("Verdant Lightbulb", .beer, 4.5, [(pint, 6.95), (can440, 4.5)]),
        ("Verdant Putty", .beer, 8.0, [(can440, 9)]),
        ("Lost & Grounded Keller Pils", .beer, 4.8, [(pint, 6.95), (can440, 4.25)]),
        ("Lost & Grounded Running With Sceptres", .beer, 5.2, [(pint, 6.95), (can440, 4.25)]),
        ("Burning Sky Arise", .beer, 4.4, [(pint, 6.6), (can440, 4.2)]),
        ("Wiper and True Kaleidoscope", .beer, 4.2, [(pint, 6.6), (can440, 3.25)]),
        ("Left Handed Giant Sky Above", .beer, 4.5, [(pint, 6.95), (can440, 4.3)]),
        ("Vocation Bread & Butter", .beer, 3.9, [(pint, 6.6), (can440, 2.13)]),
        ("Vocation Life & Death", .beer, 6.5, [(pint, 7.6), (can440, 2.58)]),
        ("Vocation Heart & Soul", .beer, 4.4, [(pint, 6.6), (can330, 1.75)]),
        ("Vocation Hop, Skip & Juice", .beer, 5.7, [(pint, 7.2), (can440, 2.5)]),
        ("Vocation Hilltop Lager", .beer, 4.3, [(pint, 6.6), (can440, 1.92)]),
        ("Abbeydale Deception", .beer, 4.1, [(pint, 6.6), (can440, 3.5)]),
        ("Brew York Golden Eagle", .beer, 4.8, [(pint, 6.95), (can440, 3.4)]),
        ("Neon Raptor Crushing Blows", .beer, 4.2, [(pint, 6.6), (can440, 4.6)]),
        ("Polly's Pilsner", .beer, 4.7, [(pint, 6.95), (can440, 4.75)]),
        ("Polly's Cherry", .beer, 4.5, [(can440, 5.5)]),
        ("Vault City Triple Fruited Mango", .beer, 4.8, [(can440, 3.75)]),
        ("Moor Revival", .beer, 3.4, [(pint, 6.6), (can440, 3)]),
        ("Donzoko Northern Helles", .beer, 4.2, [(pint, 6.6), (can440, 4.65)]),
        ("Duration Turtles All The Way Down", .beer, 5.5, [(pint, 7.2), (can440, 5.25)]),
        ("Thornbridge Lukas", .beer, 4.2, [(pint, 6.6), (can330, 2.1)]),
        ("Thornbridge Kill Your Darlings", .beer, 5.0, [(pint, 6.95), (can440, 4.5)]),
        ("Cloudwater Piccadilly Pilsner", .beer, 4.2, [(pint, 6.6), (can440, 3.72)]),
        ("Cloudwater Fuzzy", .beer, 4.2, [(pint, 6.6), (can440, 4.8)]),
        ("Cloudwater SoCal", .beer, 4.0, [(pint, 6.6), (can440, 4.65)]),
        // Arbor sell in imperial pint cans, which is why these look dear against a 440.
        ("Arbor Yakima Valley", .beer, 7.0, [(pint, 7.6), (can568, 5.25)]),
        ("Arbor Motueka", .beer, 4.0, [(pint, 6.6), (can568, 4)]),
        ("Track Sonoma", .beer, 3.8, [(pint, 6.6), (can440, 4)]),
        ("Siren Lumina", .beer, 4.2, [(pint, 6.6), (can330, 2.2)]),
        ("Siren Broken Dream", .stout, 6.5, [(pint, 7.6), (can330, 2.3)]),
        // Cask & bitter
        ("Fuller's London Pride", .beer, 4.1, [(pint, 5.6), (half, 2.8)]),
        ("Fuller's London Pride (bottle)", .beer, 4.7, [(bottle500, 2.35)]),
        ("Fuller's ESB", .beer, 5.5, [(pint, 5.3), (half, 2.65)]),
        ("Fuller's ESB (bottle)", .beer, 5.9, [(bottle500, 2.45)]),
        ("Fuller's London Porter", .beer, 5.4, [(bottle500, 2.5)]),
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
        // drinks these. Two London venues publish a Belgian bottle list — The Porterhouse in Covent
        // Garden and The Dovetail in Clerkenwell — and where both carry a beer it's priced between
        // them, since the tourist end and the specialist end disagree by up to 90p. A beer neither
        // lists takes its strength's price from them: £7 for an abbey blonde, £7.90 at 8.5%, £9 above
        // 10%. Below 6% both menus stop, so the wits and fruit beers sit at £6.50 — the one figure
        // here that's reasoned rather than read. Retail runs about £4 a bottle under all of this.
        // Lowlander and Bierschenke would have been the other two to ask; both closed in 2025.
        ("Leffe Blonde", .beer, 6.6, [(bottle330, 6.5)]),
        ("Leffe Brune", .beer, 6.5, [(bottle330, 6.7)]),
        ("Leffe Tripel", .beer, 8.5, [(bottle330, 7.9)]),
        ("Chimay Rouge", .beer, 7.0, [(bottle330, 7.6)]),
        ("Chimay Tripel", .beer, 8.0, [(bottle330, 8)]),
        ("Chimay Bleue", .beer, 9.0, [(bottle330, 8.3)]),
        ("Westmalle Dubbel", .beer, 7.0, [(bottle330, 7.5)]),
        ("Westmalle Tripel", .beer, 9.5, [(bottle330, 8.2)]),
        ("Rochefort 6", .beer, 7.5, [(bottle330, 7.5)]),
        ("Rochefort 8", .beer, 9.2, [(bottle330, 8.55)]),
        ("Rochefort 10", .beer, 11.3, [(bottle330, 9.5)]),
        ("Orval", .beer, 6.2, [(bottle330, 6.5)]),
        ("Duvel", .beer, 8.5, [(bottle330, 7.8)]),
        ("La Chouffe", .beer, 8.0, [(bottle330, 7.9)]),
        ("St Bernardus Abt 12", .beer, 10.0, [(bottle330, 8.2)]),
        ("St Bernardus Tripel", .beer, 8.0, [(bottle330, 7.5)]),
        ("St Bernardus Pater 6", .beer, 6.7, [(bottle330, 7)]),
        ("Gulden Draak", .beer, 10.5, [(bottle330, 9.5)]),
        ("Piraat", .beer, 10.5, [(bottle330, 8.5)]),
        ("Maredsous 8", .beer, 8.0, [(bottle330, 7.9)]),
        ("Maredsous 10", .beer, 10.0, [(bottle330, 9)]),
        ("Grimbergen Blonde", .beer, 6.7, [(bottle330, 6.9)]),
        ("Grimbergen Dubbel", .beer, 6.5, [(bottle330, 6.9)]),
        ("Straffe Hendrik Tripel", .beer, 9.0, [(bottle330, 8)]),
        ("Straffe Hendrik Quadrupel", .beer, 11.0, [(bottle330, 9.2)]),
        ("St Feuillien Blonde", .beer, 7.5, [(bottle330, 7.7)]),
        ("Tripel Karmeliet", .beer, 8.4, [(bottle330, 7.8)]),
        ("Delirium Tremens", .beer, 8.5, [(bottle330, 7.8)]),
        ("Delirium Nocturnum", .beer, 8.5, [(bottle330, 7.9)]),
        ("Pauwel Kwak", .beer, 8.4, [(bottle330, 7.8)]),
        ("Bush Ambrée", .beer, 12.0, [(bottle330, 9)]),
        ("Brugse Zot Blond", .beer, 6.0, [(bottle330, 7.3)]),
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
        ("Tegernseer Hell", .beer, 4.8, [(bottle500, 4.45)]),
        ("Andechs Vollbier Hell", .beer, 4.8, [(bottle500, 4.2)]),
        ("Hofbräu Münchner Weisse", .beer, 5.1, [(bottle500, 3.85)]),
        ("Weihenstephaner Hefe Weissbier", .beer, 5.4, [(bottle500, 4.6)]),
        ("Weihenstephaner Korbinian", .beer, 7.4, [(bottle500, 4.55)]),
        ("Schneider Weisse Original", .beer, 5.4, [(bottle500, 3.25)]),
        ("Schneider Weisse Aventinus", .beer, 8.2, [(bottle500, 5.6)]),
        ("Franziskaner Hefe-Weissbier", .beer, 5.0, [(bottle500, 2.6)]),
        ("Maisel's Weisse", .beer, 5.1, [(bottle500, 3.15)]),
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
        ("Stowford Press Mixed Berries", .cider, 4.0, [(can440, 1.25)]),
        ("Cornish Orchards Gold", .cider, 5.0, [(pint, 6.4), (bottle500, 2.95)]),
        // Westons. "Perry" went in February 2024 — Country Perry is Vintage Pear now, and 6% where it
        // was 7.4%. Old Rosie has been 6.8% since 2019, whatever the pub chalkboard says.
        ("Henry Westons Vintage", .cider, 8.2, [(pint, 6.9), (bottle500, 2.3)]),
        ("Henry Westons Cloudy Vintage", .cider, 7.3, [(bottle500, 2.04)]),
        ("Henry Westons 1880 Vintage", .cider, 6.2, [(bottle500, 2.5)]),
        ("Henry Westons Vintage Pear", .cider, 6.0, [(bottle500, 2.6)]),
        ("Henry Westons Organic Medium Dry", .cider, 6.0, [(bottle500, 2.38)]),
        ("Westons Wyld Wood Organic", .cider, 6.0, [(bottle500, 2.29)]),
        ("Westons Old Rosie", .cider, 6.8, [(pint, 6.2), (bottle500, 2.99)]),
        ("Kopparberg Strawberry & Lime", .cider, 4.0, [(bottle500, 2.19)]),
        ("Kopparberg Mixed Fruit", .cider, 4.0, [(bottle500, 2.34)]),
        ("Rekorderlig Strawberry & Lime", .cider, 4.0, [(bottle500, 2.6)]),
        ("Old Mout Kiwi & Lime", .cider, 4.0, [(bottle500, 2.4)]),
        // Super-strength — the corner-shop singles. Most were cut to 7.5% in the mid-2010s, years before
        // the 2023 duty reform set its higher rate at 8.5%; Kestrel and Karpackie Super Mocne are the
        // holdouts still brewed above the cliff and paying for it. The white cider prices are the ones
        // printed on the bottle, which is how that end of the trade sells: price-marked, take it or
        // leave it.
        ("Carlsberg Special Brew", .beer, 7.5, [(can500, 2.87)]),
        ("Tennent's Super", .beer, 7.5, [(can500, 2.75)]),
        ("Skol Super", .beer, 8.0, [(can500, 2)]),
        ("Kestrel Super Premium", .beer, 9.0, [(can500, 3.33)]),
        ("Karpackie Super Mocne", .beer, 9.0, [(can500, 1.99)]),
        ("K Cider", .cider, 7.5, [(can500, 2.3)]),
        ("Ace Cider", .cider, 7.5, [(can500, 1.29)]),
        // White cider is sold by the 2.5 litre bottle, which is 18 units — the pint is what gets poured.
        ("Frosty Jack's", .cider, 7.5, [(pint, 1.36), (bottle2500, 5.99)]),
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
        ("MD 20/20", .fortified, 13.0, [(glass175, 2.45), (wineBottle, 10.49)]),
        ("Sanatogen Tonic Wine", .fortified, 15.0, [(glass175, 1.25), (bottle70cl, 4.99)]),
        ("QC Sherry", .fortified, 17.5, [(schooner, 0.9), (bottle70cl, 8.99)]),
        ("Emva Cream", .fortified, 15.0, [(schooner, 1.5), (bottle70cl, 14.99)]),
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
        ("Koko Kanu", .spirit, 37.5, [(single, 6.8), (single35, 9.5), (bottle70cl, 20.6)]),
        // Overproof. A 25 ml single of Wray & Nephew carries three times the alcohol of one of Malibu,
        // which is the whole reason to log it as itself rather than as "rum". The two nobody pours by
        // the measure are bottle-only; a shot from your own bottle prices pro-rata.
        ("Wray & Nephew White Overproof", .spirit, 63.0, [(single, 7.4), (single35, 10.35), (bottle70cl, 29)]),
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
        ("Aperol Spritz", .cocktail, 8.9, [(.init(.wineGlass, 185), 11.5)]),
        ("Espresso Martini", .cocktail, 17.7, [(.init(.coupe, 140), 11.95)]),
        ("Margarita", .cocktail, 16.0, [(coupe, 11.95)]),
        ("Mojito", .cocktail, 8.0, [(doubleLong, 11.5)]),
        ("Negroni", .cocktail, 21.8, [(.init(.tumbler, 110), 10.5)]),
        ("Old Fashioned", .cocktail, 21.0, [(.init(.tumbler, 90), 12.95)]),
        ("Cosmopolitan", .cocktail, 18.0, [(smallCoupe, 11.5)]),
        ("Porn Star Martini", .cocktail, 15.2, [(.init(.coupe, 185), 12.5)]),
        ("Daiquiri", .cocktail, 25.0, [(.init(.coupe, 90), 11.5)]),
        ("Piña Colada", .cocktail, 8.0, [(doubleLong, 11.5)]),
        ("Long Island Iced Tea", .cocktail, 10.0, [(doubleLong, 11.95)]),
        ("Bloody Mary", .cocktail, 8.0, [(doubleLong, 7)]),
        ("Sangria", .cocktail, 9.0, [(glass250, 9)]),
        ("Buck's Fizz", .cocktail, 8.0, [(.init(.flute, 150), 9)]),
        ("Amaretto Sour", .cocktail, 14.0, [(.init(.tumbler, 100), 10)]),
        ("B52", .cocktail, 24.3, [(.init(.shot, 45), 5)]),
        ("Baby Guinness", .cocktail, 16.3, [(.init(.shot, 30), 5)]),
        ("Black Velvet", .cocktail, 8.1, [(.init(.flute, 150), 10)]),
        ("Blue Lagoon", .cocktail, 11.7, [(.init(.tumbler, 180), 10)]),
        ("Cantarito", .cocktail, 10.4, [(.init(.tumbler, 220), 10)]),
        ("Godfather", .cocktail, 34.8, [(.init(.tumbler, 85), 10)]),
        ("Hugo Spritz", .cocktail, 8.1, [(.init(.wineGlass, 180), 10)]),
        ("Kir Royale", .cocktail, 12.3, [(.init(.flute, 135), 10)]),
        ("Limoncello Spritz", .cocktail, 13.7, [(.init(.wineGlass, 170), 10)]),
        ("Mudslide", .cocktail, 10.6, [(.init(.tumbler, 300), 10)]),
        ("Passionfruit Martini", .cocktail, 20.1, [(.init(.coupe, 100), 10)]),
        ("Salty Dog", .cocktail, 15.6, [(.init(.tumbler, 120), 10)]),
        ("Screwdriver", .cocktail, 14.4, [(.init(.tumbler, 130), 10)]),
        ("Snakebite", .cocktail, 4.5, [(.init(.pint, 568), 6.5)]),
        ("Snowball", .cocktail, 5.1, [(.init(.tumbler, 200), 10)]),
        ("White Russian", .cocktail, 19.5, [(.init(.tumbler, 140), 10)]),
        ("Woo Woo", .cocktail, 10.4, [(.init(.tumbler, 130), 10)]),
        ("Alexander", .cocktail, 18.3, [(.init(.coupe, 105), 10)]),
        ("Americano", .cocktail, 13.3, [(.init(.tumbler, 90), 10)]),
        ("Angel Face", .cocktail, 31.2, [(.init(.coupe, 100), 10)]),
        ("Aviation", .cocktail, 26.4, [(.init(.coupe, 90), 10)]),
        ("Between the Sheets", .cocktail, 25.8, [(.init(.coupe, 125), 10)]),
        ("Boulevardier", .cocktail, 24.0, [(.init(.coupe, 125), 10)]),
        ("Brandy Crusta", .cocktail, 26.3, [(.init(.coupe, 100), 10)]),
        ("Casino", .cocktail, 22.2, [(.init(.tumbler, 90), 10)]),
        ("Clover Club", .cocktail, 20.0, [(.init(.coupe, 90), 10)]),
        ("Dry Martini", .cocktail, 30.4, [(.init(.coupe, 85), 10)]),
        ("Gin Fizz", .cocktail, 15.7, [(.init(.tumbler, 115), 10)]),
        ("Hanky Panky", .cocktail, 24.1, [(.init(.coupe, 115), 10)]),
        ("John Collins", .cocktail, 11.2, [(.init(.tumbler, 160), 10)]),
        ("Last Word", .cocktail, 28.6, [(.init(.coupe, 100), 10)]),
        ("Manhattan", .cocktail, 30.5, [(.init(.coupe, 85), 10)]),
        ("Martinez", .cocktail, 23.6, [(.init(.coupe, 115), 10)]),
        ("Mary Pickford", .cocktail, 16.8, [(.init(.coupe, 115), 10)]),
        ("Monkey Gland", .cocktail, 20.9, [(.init(.coupe, 135), 10)]),
        ("Paradise", .cocktail, 22.4, [(.init(.coupe, 75), 10)]),
        ("Planter's Punch", .cocktail, 13.8, [(.init(.tumbler, 130), 10)]),
        ("Porto Flip", .cocktail, 18.8, [(.init(.coupe, 80), 10)]),
        ("Ramos Gin Fizz", .cocktail, 6.0, [(.init(.tumbler, 300), 10)]),
        ("Remember the Maine", .cocktail, 31.2, [(.init(.coupe, 117), 10)]),
        ("Rusty Nail", .cocktail, 32.9, [(.init(.tumbler, 85), 10)]),
        ("Sazerac", .cocktail, 32.9, [(.init(.tumbler, 67), 10)]),
        ("Sidecar", .cocktail, 26.0, [(.init(.coupe, 100), 10)]),
        ("Stinger", .cocktail, 31.0, [(.init(.coupe, 80), 10)]),
        ("Tuxedo", .cocktail, 25.3, [(.init(.coupe, 80), 10)]),
        ("Vieux Carré", .cocktail, 28.4, [(.init(.coupe, 115), 10)]),
        ("Whiskey Sour", .cocktail, 17.1, [(.init(.coupe, 105), 10)]),
        ("White Lady", .cocktail, 25.0, [(.init(.coupe, 100), 10)]),
        ("Bee's Knees", .cocktail, 16.2, [(.init(.coupe, 130), 10)]),
        ("Bramble", .cocktail, 15.9, [(.init(.tumbler, 140), 10)]),
        ("Canchánchara", .cocktail, 16.0, [(.init(.tumbler, 150), 10)]),
        ("Chartreuse Swizzle", .cocktail, 13.2, [(.init(.tumbler, 200), 10)]),
        ("Dark 'n' Stormy", .cocktail, 13.3, [(.init(.tumbler, 180), 10)]),
        ("Don's Special Daiquiri", .cocktail, 6.9, [(.init(.tumbler, 260), 10)]),
        ("Fernandito", .cocktail, 9.8, [(.init(.tumbler, 200), 10)]),
        ("French Martini", .cocktail, 22.8, [(.init(.coupe, 90), 10)]),
        ("Gin Basil Smash", .cocktail, 19.2, [(.init(.coupe, 125), 10)]),
        ("Grand Margarita", .cocktail, 26.1, [(.init(.tumbler, 115), 10)]),
        ("IBA Tiki", .cocktail, 10.7, [(.init(.tumbler, 270), 10)]),
        ("Illegal", .cocktail, 19.0, [(.init(.coupe, 130), 10)]),
        ("Jungle Bird", .cocktail, 14.3, [(.init(.tumbler, 165), 10)]),
        ("Missionary's Downfall", .cocktail, 5.2, [(.init(.coupe, 320), 10)]),
        ("Naked and Famous", .cocktail, 18.6, [(.init(.coupe, 110), 10)]),
        ("New York Sour", .cocktail, 17.3, [(.init(.tumbler, 150), 10)]),
        ("Old Cuban", .cocktail, 15.5, [(.init(.coupe, 165), 10)]),
        ("Paloma", .cocktail, 11.4, [(.init(.tumbler, 175), 10)]),
        ("Paper Plane", .cocktail, 17.8, [(.init(.coupe, 145), 10)]),
        ("Penicillin", .cocktail, 20.9, [(.init(.tumbler, 130), 10)]),
        ("Pisco Punch", .cocktail, 18.4, [(.init(.coupe, 150), 10)]),
        ("Russian Spring Punch", .cocktail, 12.1, [(.init(.tumbler, 170), 10)]),
        ("Sherry Cobbler", .cocktail, 13.3, [(.init(.tumbler, 125), 10)]),
        ("South Side", .cocktail, 18.5, [(.init(.coupe, 130), 10)]),
        ("Spicy Fifty", .cocktail, 17.0, [(.init(.coupe, 110), 10)]),
        ("Suffering Bastard", .cocktail, 12.5, [(.init(.tumbler, 195), 10)]),
        ("Three Dots and a Dash", .cocktail, 9.8, [(.init(.tumbler, 320), 10)]),
        ("Tipperary", .cocktail, 28.2, [(.init(.coupe, 115), 10)]),
        ("Tommy's Margarita", .cocktail, 17.1, [(.init(.tumbler, 140), 10)]),
        ("Trinidad Sour", .cocktail, 19.9, [(.init(.coupe, 135), 10)]),
        ("Ve.N.To", .cocktail, 15.0, [(.init(.tumbler, 120), 10)]),
        // An absinthe rinse is poured out, but it isn't gone: about 2 ml of 68% clings to the glass, which
        // the Sazerac and Remember the Maine are counted with. The rest of the pour isn't, because it's in
        // the sink. Nothing else here is rinsed — a French 75 and a Dry Martini have no absinthe in them.
        // The IBA's own specs, with the strength worked out from the measures rather than guessed:
        // alcohol in the glass over the liquid in the glass, ice melt included. That's why a Zombie
        // is five units in a tumbler and a Bellini is under one in a flute. Glass volumes are a
        // bartender's estimate of the pour as drunk — nobody publishes dilution figures per drink.
        // A tenner each, which is roughly London and exactly nowhere.
("Bellini", .cocktail, 7.3, [(.init(.flute, 150), 10)]),
        ("Black Russian", .cocktail, 25.8, [(.init(.tumbler, 90), 10)]),
        ("Caipirinha", .cocktail, 18.5, [(.init(.tumbler, 130), 10)]),
        ("Cardinale", .cocktail, 26.0, [(.init(.coupe, 85), 10)]),
        ("Champagne Cocktail", .cocktail, 14.9, [(.init(.flute, 105), 10)]),
        ("Corpse Reviver #2", .cocktail, 20.5, [(.init(.coupe, 145), 10)]),
        ("Cuba Libre", .cocktail, 8.7, [(.init(.tumbler, 215), 10)]),
        ("French 75", .cocktail, 13.7, [(.init(.flute, 140), 10)]),
        ("French Connection", .cocktail, 26.4, [(.init(.tumbler, 90), 10)]),
        ("Garibaldi", .cocktail, 5.8, [(.init(.tumbler, 195), 10)]),
        ("Grasshopper", .cocktail, 11.0, [(.init(.coupe, 80), 10)]),
        ("Hemingway Special", .cocktail, 17.6, [(.init(.coupe, 155), 10)]),
        ("Horse's Neck", .cocktail, 8.7, [(.init(.tumbler, 190), 10)]),
        ("Irish Coffee", .cocktail, 8.9, [(.init(.tumbler, 225), 10)]),
        ("Kir", .cocktail, 12.3, [(.init(.wineGlass, 100), 10)]),
        ("Lemon Drop Martini", .cocktail, 23.5, [(.init(.coupe, 85), 10)]),
        ("Mai Tai", .cocktail, 17.3, [(.init(.tumbler, 165), 10)]),
        ("Mimosa", .cocktail, 5.5, [(.init(.flute, 150), 10)]),
        ("Mint Julep", .cocktail, 20.9, [(.init(.tumbler, 115), 10)]),
        ("Moscow Mule", .cocktail, 9.0, [(.init(.tumbler, 200), 10)]),
        ("Pisco Sour", .cocktail, 15.0, [(.init(.coupe, 160), 10)]),
        ("Rabo de Galo", .cocktail, 25.6, [(.init(.tumbler, 115), 10)]),
        ("Sea Breeze", .cocktail, 7.3, [(.init(.tumbler, 220), 10)]),
        ("Sex on the Beach", .cocktail, 11.2, [(.init(.tumbler, 170), 10)]),
        ("Singapore Sling", .cocktail, 9.6, [(.init(.tumbler, 230), 10)]),
        ("Tequila Sunrise", .cocktail, 9.5, [(.init(.tumbler, 180), 10)]),
        ("Vesper", .cocktail, 28.7, [(.init(.coupe, 88), 10)]),
        ("Zombie", .cocktail, 15.2, [(.init(.tumbler, 330), 10)]),
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
        // Aldi and Lidl's own labels. Priced as the shop sells them, which is the only way they're
        // sold — there's no bar pouring Old Hopking, so a measure of one prices off the bottle.
        ("Galahad Premium Lager", .beer, 4.0, [(can440, 2.99)]),
        ("Rheinbacher Premium Pilsner", .beer, 4.5, [(can500, 3.99)]),
        ("Anti-Establishment IPA", .beer, 5.6, [(can440, 1.99)]),
        ("Anti-Establishment Hazy Daisy IPA", .beer, 5.0, [(can440, 1.99)]),
        ("Anti-Establishment Found Lager", .beer, 4.0, [(can440, 2)]),
        ("Anti-Establishment Mango Joiva Lager", .beer, 4.0, [(can440, 1.49)]),
        ("Anti-Establishment Peach Joiva Lager", .beer, 4.0, [(can440, 1.49)]),
        ("Perlenbacher Pilsner", .beer, 4.5, [(bottle500, 1.29)]),
        ("Hatherwood Golden Goose", .beer, 4.5, [(bottle500, 1.09)]),
        ("Hatherwood Ruby Rooster", .beer, 3.8, [(bottle500, 1.09)]),
        ("Taurus Original Cider", .cider, 5.0, [(can440, 2.29), (bottle2000, 1.89)]),
        ("Taurus Pear Cider", .cider, 4.8, [(can440, 2.29)]),
        ("Highland Black Scotch Whisky", .spirit, 40.0, [(single, 0.55), (bottle70cl, 15.35)]),
        ("Glen Marnoch Speyside Single Malt", .spirit, 40.0, [(single, 0.66), (bottle70cl, 18.49)]),
        ("Queen Margot Blended Scotch Whisky", .spirit, 40.0, [(single, 0.48), (bottle70cl, 13.49)]),
        ("Greyson's London Dry Gin", .spirit, 37.5, [(single, 0.43), (bottle70cl, 11.99), (bottle1l, 16.79)]),
        ("Hortus Artisan London Dry Gin", .spirit, 40.0, [(single, 0.61), (bottle70cl, 16.99)]),
        ("Hortus Rhubarb & Ginger Gin Liqueur", .spirit, 20.0, [(single, 0.43), (bottle70cl, 11.99)]),
        ("Hortus Scottish Raspberry Gin Liqueur", .spirit, 20.0, [(single, 0.43), (bottle70cl, 11.99)]),
        ("Rachmaninoff Triple Distilled Vodka", .spirit, 37.5, [(single, 0.36), (bottle70cl, 9.99)]),
        ("Old Hopking White Rum", .spirit, 37.5, [(single, 0.44), (bottle70cl, 12.25)]),
        ("Old Hopking Dark Rum", .spirit, 37.5, [(single, 0.43), (bottle70cl, 11.99)]),
        ("Old Hopking Spiced Rum", .spirit, 35.0, [(single, 0.43), (bottle70cl, 11.99)]),
        ("Ballycastle Country Cream", .spirit, 12.0, [(port, 0.4), (bottle70cl, 5.59)]),
        ("Specially Selected Rioja Reserva", .redWine, 14.2, [(glass175, 1.86), (wineBottle, 7.99)]),
        ("Cepa Lebrel Crianza", .redWine, 15.0, [(glass175, 1.35), (wineBottle, 5.79)]),
        ("Veuve Monsigny Champagne Brut", .bubbles, 12.5, [(flute, 2.67), (wineBottle, 15.99)]),
        ("Costellore Prosecco", .bubbles, 10.5, [(flute, 0.91), (wineBottle, 5.45)]),
        ("Belletti Hugo Spritz", .alcopop, 6.9, [(flute, 0.67), (wineBottle, 3.99)]),
    ]

    static let brands: [CatalogBrand] = entries.map { CatalogBrand(name: $0.0, category: $0.1, abv: $0.2, serves: $0.3) }

    static let items: [CatalogItem] = brands.flatMap { brand in
        brand.serves.map { CatalogItem(name: brand.name, category: brand.category, vessel: $0.size.vessel, volumeMl: $0.size.ml, abv: brand.abv, price: $0.price) }
    }

    static let brandsByCategory: [DrinkCategory: [CatalogBrand]] = Dictionary(grouping: brands, by: \.category)

    /// What a brand is searched by, folded once — searching is per keystroke over a couple of thousand
    /// serves, and folding each on the way is most of what a keystroke cost.
    private static let searchKeys: [String] = items.map { "\($0.name) \($0.category.label)".searchFolded }

    /// A drink's identity as the catalogue sees it: same name, same kind.
    static func key(_ name: String, _ category: DrinkCategory) -> String { "\(name)|\(category.rawValue)" }

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

    /// A size the brand isn't listed in scales from the nearest serve of the same vessel before any other:
    /// a 440 ml bottle is the 330's price and a third, not a pint's less a fifth. Draught and packaged are
    /// different trades and their prices don't divide into one another.
    static func price(_ brand: CatalogBrand, _ vessel: Vessel, _ ml: Double) -> Double {
        if let exact = brand.serves.first(where: { $0.size.vessel == vessel && $0.size.ml == ml }) { return exact.price }
        let alike = brand.serves.filter { $0.size.vessel == vessel }
        guard let nearest = alike.min(by: { abs($0.size.ml - ml) < abs($1.size.ml - ml) }) ?? brand.serves.first
        else { return 0 }
        return nearest.price * ml / nearest.size.ml
    }

    static func search(_ query: String) -> [CatalogItem] {
        let query = query.trimmingCharacters(in: .whitespaces).searchFolded
        guard !query.isEmpty else { return [] }
        return zip(items, searchKeys).filter { $0.1.contains(query) }.map(\.0)
    }
}

nonisolated extension String {
    /// Case and accents folded, so "stella" finds Stella and "kolsch" finds Kölsch.
    var searchFolded: String { folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
}
