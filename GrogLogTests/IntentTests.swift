import Foundation
import GRDB
import Testing
@testable import GrogLog

/// The intent parameter is a `Serve.key`, so it has to survive the round trip to a string and back —
/// at the price the drink is pinned at, not the one baked into the key.
@Suite struct ServeKeyTests {
    private func database() throws -> DatabaseQueue {
        let database = try AppDatabase.inMemory()
        return database.writer as! DatabaseQueue
    }

    @Test func keyResolvesBackToTheSameDrinkAndSize() throws {
        let writer = try database()
        let drink = Drink(name: "Staropramen", category: .beer, abv: 5, vessel: .can, volumeMl: 440, price: 2)
        try writer.write { try drink.insert($0) }
        let serve = Serve(drink, .bottle, 660)

        let found = try writer.read { try Serve.matching(serve.id, $0) }
        #expect(found?.drink.id == drink.id)
        #expect(found?.vessel == .bottle)
        #expect(found?.volumeMl == 660)
    }

    @Test func aPinnedSizeResolvesAtThePriceYouPayForIt() throws {
        let writer = try database()
        let drink = Drink(name: "Doom Bar", category: .beer, abv: 4, vessel: .pint, volumeMl: 568, price: 4)
        try writer.write { db in
            try drink.insert(db)
            try Favourite(drinkId: drink.id, vessel: .pint, volumeMl: 568, price: 6.20).insert(db)
        }

        let found = try writer.read { try Serve.matching(Serve.key(drink.id, .pint, 568), $0) }
        #expect(found?.price == 6.20)
    }

    @Test func anUnpinnedSizeFallsBackToTheDrinksPrice() throws {
        let writer = try database()
        let drink = Drink(name: "Doom Bar", category: .beer, abv: 4, vessel: .pint, volumeMl: 568, price: 4)
        try writer.write { try drink.insert($0) }

        let found = try writer.read { try Serve.matching(Serve.key(drink.id, .half, 284), $0) }
        #expect(found?.price == 2)
    }

    @Test func aKeyForADrinkThatsGoneResolvesToNothing() throws {
        let writer = try database()
        let found = try writer.read { try Serve.matching(Serve.key(UUID(), .pint, 568), $0) }
        #expect(found == nil)
    }

    @Test func rubbishResolvesToNothingRatherThanCrashing() throws {
        let writer = try database()
        for key in ["", "nonsense", "a|b", "\(UUID().uuidString)|pint"] {
            #expect(try writer.read { try Serve.matching(key, $0) } == nil)
        }
    }

    @Test func suggestionsPutTheMostRecentlyDrunkFirstAndLeaveHiddenDrinksOut() throws {
        let writer = try database()
        let lager = Drink(name: "Lager", category: .beer, abv: 4, vessel: .pint, volumeMl: 568)
        let wine = Drink(name: "Wine", category: .redWine, abv: 12, vessel: .wineGlass, volumeMl: 175)
        let gone = Drink(name: "Gone", category: .beer, abv: 4, vessel: .pint, volumeMl: 568, isHidden: true)
        try writer.write { db in
            for drink in [lager, wine, gone] { try drink.insert(db) }
            try Favourite(drinkId: lager.id, vessel: .pint, volumeMl: 568, price: 5, sortOrder: 0).insert(db)
            try Favourite(drinkId: wine.id, vessel: .wineGlass, volumeMl: 175, price: 7, sortOrder: 1, lastUsed: .now).insert(db)
            try Favourite(drinkId: gone.id, vessel: .pint, volumeMl: 568, price: 5, sortOrder: 2, lastUsed: .now).insert(db)
        }

        let grid = try writer.read { try Serve.grid($0) }
        #expect(grid.map(\.drink.name) == ["Wine", "Lager"])
    }
}
