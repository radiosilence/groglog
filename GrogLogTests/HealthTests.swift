import Foundation
import Testing
@testable import GrogLog

/// Health counts standard drinks, not UK units. Getting this wrong doesn't fail — it just quietly overstates
/// every reading by three quarters, which is why it's pinned down here.
@Suite struct StandardDrinkTests {
    private func entry(ml: Double, abv: Double) -> Entry {
        let drink = Drink(name: "Beer", category: .beer, abv: abv, vessel: .pint, volumeMl: ml)
        return Entry(pour: Pour(drinkId: drink.id, timestamp: .now, day: 0, vessel: .pint, volumeMl: ml, price: 0), drink: drink)
    }

    @Test func oneUnitIsAboutFiveEighthsOfAStandardDrink() {
        // 10 ml of alcohol against Health's 17.7.
        let oneUnit = entry(ml: 1000, abv: 1)
        #expect(abs(oneUnit.units - 1) < 0.0001)
        #expect(abs(oneUnit.standardDrinks - 0.5636) < 0.001)
    }

    @Test func aPintOfFivePercentIsOneAndAHalfStandardDrinks() {
        let pint = entry(ml: 568, abv: 5)
        #expect(abs(pint.units - 2.84) < 0.0001)
        #expect(abs(pint.standardDrinks - 1.6) < 0.01)
    }

    @Test func unitsAreNeverHandedOverAsDrinks() {
        let pint = entry(ml: 568, abv: 5)
        #expect(pint.standardDrinks < pint.units)
    }

    @Test func nothingDrunkIsNoDrinks() {
        #expect(entry(ml: 330, abv: 0).standardDrinks == 0)
    }
}
