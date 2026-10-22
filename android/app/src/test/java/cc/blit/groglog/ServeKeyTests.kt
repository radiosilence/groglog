package cc.blit.groglog

import cc.blit.groglog.data.Serves
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Favourite
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.Vessel
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * A serve carried outside the app is a `Serve.key`, so it must survive the round trip to a string and back, at the
 * price the drink is pinned at rather than one encoded in the key.
 */
@RunWith(RobolectricTestRunner::class)
class ServeKeyTests {
    @Test fun keyResolvesBackToTheSameDrinkAndSize() = runBlocking {
        val database = database()
        val drink = Drink(name = "Staropramen", category = DrinkCategory.BEER, abv = 5.0, vessel = Vessel.CAN, volumeMl = 440.0, price = 2.0)
        database.rows().insert(drink)
        val serve = Serve(drink, Vessel.BOTTLE, 660.0)

        val found = Serves.matching(serve.id, database)
        assertEquals(drink.id, found?.drink?.id)
        assertEquals(Vessel.BOTTLE, found?.vessel)
        assertEquals(660.0, found?.volumeMl)
    }

    @Test fun aPinnedSizeResolvesAtThePriceYouPayForIt() = runBlocking {
        val database = database()
        val drink = Drink(name = "Doom Bar", category = DrinkCategory.BEER, abv = 4.0, vessel = Vessel.PINT, volumeMl = 568.0, price = 4.0)
        database.rows().insert(drink)
        database.rows().insert(Favourite(drinkId = drink.id, vessel = Vessel.PINT, volumeMl = 568.0, price = 6.20))

        assertEquals(6.20, Serves.matching(Serve.key(drink.id, Vessel.PINT, 568.0), database)?.price)
    }

    @Test fun anUnpinnedSizeFallsBackToTheDrinksPrice() = runBlocking {
        val database = database()
        val drink = Drink(name = "Doom Bar", category = DrinkCategory.BEER, abv = 4.0, vessel = Vessel.PINT, volumeMl = 568.0, price = 4.0)
        database.rows().insert(drink)

        assertEquals(2.0, Serves.matching(Serve.key(drink.id, Vessel.HALF, 284.0), database)?.price)
    }

    @Test fun aKeyForADrinkThatsGoneResolvesToNothing() = runBlocking {
        assertNull(Serves.matching(Serve.key(UUID.randomUUID(), Vessel.PINT, 568.0), database()))
    }

    @Test fun rubbishResolvesToNothingRatherThanCrashing() = runBlocking {
        val database = database()
        for (key in listOf("", "nonsense", "a|b", "${UUID.randomUUID()}|pint")) {
            assertNull(key, Serves.matching(key, database))
        }
    }

    @Test fun suggestionsPutTheMostRecentlyDrunkFirstAndLeaveHiddenDrinksOut() = runBlocking {
        val database = database()
        val lager = Drink(name = "Lager", category = DrinkCategory.BEER, abv = 4.0, vessel = Vessel.PINT, volumeMl = 568.0)
        val wine = Drink(name = "Wine", category = DrinkCategory.RED_WINE, abv = 12.0, vessel = Vessel.WINE_GLASS, volumeMl = 175.0)
        val gone = Drink(name = "Gone", category = DrinkCategory.BEER, abv = 4.0, vessel = Vessel.PINT, volumeMl = 568.0, isHidden = true)
        val rows = database.rows()
        for (drink in listOf(lager, wine, gone)) rows.insert(drink)
        rows.insert(Favourite(drinkId = lager.id, vessel = Vessel.PINT, volumeMl = 568.0, price = 5.0, sortOrder = 0))
        rows.insert(Favourite(drinkId = wine.id, vessel = Vessel.WINE_GLASS, volumeMl = 175.0, price = 7.0, sortOrder = 1, lastUsed = Instant.now()))
        rows.insert(Favourite(drinkId = gone.id, vessel = Vessel.PINT, volumeMl = 568.0, price = 5.0, sortOrder = 2, lastUsed = Instant.now()))

        assertEquals(listOf("Wine", "Lager"), Serves.grid(database).map { it.drink.name })
    }

    @Test fun withNothingPinnedSuggestionsOfferTheGenerics() = runBlocking {
        val database = database()
        val rows = database.rows()
        rows.insert(Drink(name = "Cider", category = DrinkCategory.CIDER, abv = 4.5, vessel = Vessel.PINT, volumeMl = 568.0, isGeneric = true, sortOrder = 102))
        rows.insert(Drink(name = "Beer", category = DrinkCategory.BEER, abv = 4.0, vessel = Vessel.PINT, volumeMl = 568.0, isGeneric = true, sortOrder = 100))
        rows.insert(Drink(name = "Units", category = DrinkCategory.UNITS, abv = 100.0, vessel = Vessel.SHOT, volumeMl = 10.0, isGeneric = true, sortOrder = 99))

        assertEquals(listOf("Beer", "Cider"), Serves.grid(database).map { it.drink.name })
    }
}
