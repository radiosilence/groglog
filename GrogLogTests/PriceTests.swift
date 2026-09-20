import Foundation
import Testing
@testable import GrogLog

/// A drink at £0.00 doesn't look broken, it looks free — it just quietly flattens the spend charts.
/// These are the lookups the backfill migration repairs old databases with.
@Suite struct PriceTests {
    @Test func everySizeOfEveryBrandCostsSomething() {
        for brand in Catalog.brands {
            for serve in brand.serves {
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

/// What separates a brand you copied in and left alone from one you've made your own. The Drinks screen sorts on
/// it, so a night of logging brands doesn't bury the drinks you actually wrote.
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

    @Test func aGenericIsNotACatalogueBrand() {
        #expect(!Catalog.holds(name: "Beer", category: .beer, abv: DrinkCategory.beer.defaultABV))
    }
}
