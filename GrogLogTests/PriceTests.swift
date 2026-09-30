import Foundation
import Testing
@testable import GrogLog

/// A drink at £0.00 looks free rather than broken, and silently flattens the spend charts.
/// These are the lookups the backfill migration uses to repair old databases.
@Suite struct PriceTests {
    @Test func everySizeOfEveryBrandCostsSomething() {
        for brand in Catalog.brands {
            for serve in brand.prices.values.flatMap({ $0 }) {
                #expect(serve.price > 0, "\(brand.name) \(serve.size.label)")
            }
        }
    }

    @Test func genericsKnowWhatTheirOwnServesCost() {
        #expect(Seed.price(name: "Beer", vessel: .pint, ml: 568) ?? 0 > 0)
        #expect(Seed.price(name: "Beer", vessel: .can, ml: 440) ?? 0 > 0)
        #expect(Seed.price(name: "Red wine", vessel: .wineGlass, ml: 175) ?? 0 > 0)
    }

    @Test func nothingIsPricedAtZeroRatherThanUnknown() {
        #expect(Seed.price(name: "Beer", vessel: .wineGlass, ml: 175) == nil)
        #expect(Seed.price(name: "Not a drink", vessel: .pint, ml: 568) == nil)
        #expect(Catalog.price(name: "Not a drink", category: .beer, vessel: .pint, ml: 568) == nil)
    }

    /// The lookup the reset button and the backfill both go through.
    @Test func aKnownBrandIsPricedAheadOfAnyGeneric() throws {
        let stella = try #require(Catalog.price(name: "Stella Artois", category: .beer, vessel: .pint, ml: 568))
        #expect(stella > 0)
        #expect(stella != Seed.price(name: "Beer", vessel: .pint, ml: 568))
    }

    @Test func aBrandPricesASizeItIsntSoldInByVolume() throws {
        let stella = try #require(Catalog.brands.first { $0.name == "Stella Artois" })
        let pint = Catalog.price(stella, .pint, 568)
        #expect(pint > 0)
        // 330 ml is on its list; 568 ml in a can is not, so it's scaled off the first serve.
        #expect(Catalog.price(stella, .bottle, 330) > 0)
        #expect(Catalog.price(stella, .can, 568) > 0)
    }
}

/// Distinguishes a catalogue brand copied in unchanged from one the user has edited. The Drinks screen sorts on it,
/// so a night of logging brands does not bury the drinks the user wrote.
@Suite struct AdoptedDrinkTests {
    private func stella() throws -> CatalogBrand {
        try #require(Catalog.brands.first { $0.name == "Stella Artois" })
    }

    @Test func aBrandCopiedInAndLeftAloneIsStillTheCatalogues() throws {
        let brand = try stella()
        #expect(Catalog.holds(name: brand.name, category: brand.category, abv: brand.abv))
    }

    @Test func changingTheStrengthMakesItYours() throws {
        let brand = try stella()
        #expect(!Catalog.holds(name: brand.name, category: brand.category, abv: brand.abv + 0.1))
    }

    @Test func renamingItMakesItYours() throws {
        let brand = try stella()
        #expect(!Catalog.holds(name: "\(brand.name) (the good one)", category: brand.category, abv: brand.abv))
    }

    @Test func aDrinkYouInventedWasNeverTheCatalogues() {
        #expect(!Catalog.holds(name: "Dave's shed cider", category: .cider, abv: 7))
    }

    /// A pint doesn't divide into a bottle. Asahi is £7.40 on draught and £1.63 for the 330, and scaling
    /// the pint by volume would log the bottle at £4.30.
    @Test func anotherSizeComesFromTheCatalogueRatherThanTheArithmetic() throws {
        let asahi = try #require(Catalog.brands.first { $0.name == "Asahi Super Dry" })
        let pint = Drink(name: asahi.name, category: asahi.category, abv: asahi.abv,
                         vessel: .pint, volumeMl: 568, price: Catalog.price(asahi, .pint, 568))
        #expect(abs(pint.price(for: .bottle, ml: 330) - Catalog.price(asahi, .bottle, 330)) < 0.001)
        #expect(pint.price(for: .bottle, ml: 330) < pint.price * 330 / 568)
        // Its own size keeps its own price.
        #expect(pint.price(for: .pint, ml: 568) == pint.price)
    }

    /// A price the user sets applies to the size it was set on. Another size is another product, looked up
    /// in the catalogue rather than scaled from this one.
    @Test func yourOwnPriceHoldsForYourOwnSizeAndNoOther() throws {
        let asahi = try #require(Catalog.brands.first { $0.name == "Asahi Super Dry" })
        let mine = Drink(name: asahi.name, category: asahi.category, abv: asahi.abv,
                         vessel: .pint, volumeMl: 568, price: 5)
        #expect(mine.price(for: .pint, ml: 568) == 5)
        #expect(abs(mine.price(for: .bottle, ml: 330) - Catalog.price(asahi, .bottle, 330)) < 0.001)
    }

    /// A drink priced only in pounds is converted for someone paying in another currency, and never for someone
    /// paying in pounds.
    @Test func aPriceIsConvertedIntoYourCurrency() throws {
        let asahi = try #require(Catalog.brands.first { $0.name == "Asahi Super Dry" })
        let pounds = Catalog.price(asahi, .pint, 568, currency: "GBP")
        let euros = Catalog.price(asahi, .pint, 568, currency: "EUR")
        #expect(pounds == asahi.prices["GBP"]?.first { $0.size.vessel == .pint }?.price)
        #expect(abs(euros - pounds * Rates.perPound["EUR"]!) < 0.001)
        #expect(Catalog.price(asahi, .pint, 568, currency: "XXX") == 0)
    }

    /// A drink of your own invention has nothing to look up, so its price is all there is to go on.
    @Test func aDrinkOfYourOwnIsTheOneThingStillScaled() {
        let shed = Drink(name: "Dave's shed cider", category: .cider, abv: 7, vessel: .bottle, volumeMl: 500, price: 3)
        #expect(abs(shed.price(for: .bottle, ml: 250) - 1.5) < 0.001)
    }

    /// A size nobody lists scales from the nearest serve of the same kind, not from whatever came first.
    @Test func anUnlistedSizeScalesFromItsOwnKindOfServe() throws {
        let asahi = try #require(Catalog.brands.first { $0.name == "Asahi Super Dry" })
        let bottle330 = Catalog.price(asahi, .bottle, 330)
        #expect(abs(Catalog.price(asahi, .bottle, 660) - bottle330 * 2) < 0.001)
    }

    @Test func aGenericIsNotACatalogueBrand() {
        #expect(!Catalog.holds(name: "Beer", category: .beer, abv: DrinkCategory.beer.defaultABV))
    }

    /// Lookups go by name and kind, so two brands sharing both would leave one of them unreachable.
    @Test func noTwoBrandsShareANameAndKind() {
        let keys = Catalog.brands.map { Catalog.key($0.name, $0.category) }
        #expect(Set(keys).count == keys.count, "\(Dictionary(grouping: keys, by: \.self).filter { $1.count > 1 }.keys.sorted())")
    }
}
