package cc.blit.groglog

import cc.blit.groglog.data.Serves
import cc.blit.groglog.data.Settings
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Favourite
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.widget.QuickLog
import cc.blit.groglog.widget.Today
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * What a widget tile, the Quick Settings tile and a launcher shortcut do when tapped: log a `Serve.key` through the same
 * `Logbook` transaction as the Log grid, and report where the day stands.
 */
@RunWith(RobolectricTestRunner::class)
class QuickLogTests {
    private val now = Instant.parse("2026-10-09T19:30:00Z")
    private val staropramen = Drink(name = "Staropramen", category = DrinkCategory.BEER, abv = 5.0, vessel = Vessel.PINT, volumeMl = 568.0, price = 5.0)

    @Test fun aTileLogsItsDrinkAtThePinnedPrice() = runBlocking {
        val database = database()
        database.rows().insert(staropramen)
        database.rows().insert(Favourite(drinkId = staropramen.id, vessel = Vessel.PINT, volumeMl = 568.0, price = 6.20))

        val logged = QuickLog.log(Serve(staropramen).id, database, Settings(), now)

        val pours = database.rows().pours()
        assertEquals(1, pours.size)
        assertEquals(6.20, pours[0].price, 0.0)
        assertEquals(now, pours[0].timestamp)
        assertTrue(near(2.84, logged!!.units))
        assertEquals("2.8 units today.", logged.summary)
    }

    @Test fun theReportIsTheDaysTotalNotJustTheDrink() = runBlocking {
        val database = database()
        database.rows().insert(staropramen)
        val key = Serve(staropramen).id

        QuickLog.log(key, database, Settings(), now)
        val logged = QuickLog.log(key, database, Settings(), now.plusSeconds(1800))

        assertTrue(near(5.68, logged!!.units))
        assertEquals(1, database.rows().days().size)
        assertTrue(near(5.68, database.rows().days()[0].units))
    }

    @Test fun withAGoalTheReportSaysWhatIsLeft() = runBlocking {
        val database = database()
        database.rows().insert(staropramen)
        val settings = Settings(goal = Goal(isEnabled = true, baselineWeekly = 28.0, start = now))

        val logged = QuickLog.log(Serve(staropramen).id, database, settings, now)

        assertEquals(4.0, logged!!.budget!!, 0.0001)
        assertEquals("2.8 units today, 1.2 of 4.0 left.", logged.summary)
    }

    @Test fun aTileForADrinkThatsGoneLogsNothing() = runBlocking {
        val database = database()

        assertNull(QuickLog.log(Serve.key(UUID.randomUUID(), Vessel.PINT, 568.0), database, Settings(), now))
        assertTrue(database.rows().pours().isEmpty())
        assertTrue(database.rows().days().isEmpty())
    }

    @Test fun loggingMovesTheDrinkToTheFrontOfTheTiles() = runBlocking {
        val database = database()
        val wine = Drink(name = "Red wine", category = DrinkCategory.RED_WINE, abv = 12.0, vessel = Vessel.WINE_GLASS, volumeMl = 175.0)
        for (drink in listOf(staropramen, wine)) {
            database.rows().insert(drink)
            database.rows().insert(Favourite(drinkId = drink.id, vessel = drink.vessel, volumeMl = drink.volumeMl, price = drink.price))
        }

        QuickLog.log(Serve(wine).id, database, Settings(), now)

        assertEquals(listOf("Red wine", "Staropramen"), Serves.grid(database).map { it.drink.name })
    }

    @Test fun theWidgetsSeeATileTapAtOnce() = runBlocking {
        val database = database()
        val prefs = prefs()
        database.rows().insert(staropramen)
        database.rows().insert(Favourite(drinkId = staropramen.id, vessel = Vessel.PINT, volumeMl = 568.0, price = 5.0))
        val today = Today.observe(database, prefs)
        assertEquals(0.0, today.first().units, 0.0)

        QuickLog.log(Serve(staropramen).id, database, prefs.current())

        val after = today.first()
        assertTrue(near(2.84, after.units))
        assertEquals(listOf("Staropramen"), after.tiles.map { it.drink.name })
        assertTrue(near(2.84, after.curve.last().units))
    }

    @Test fun hiddenDrinksAndUnitsAreNotTiles() = runBlocking {
        val database = database()
        val hidden = staropramen.copy(id = UUID.randomUUID(), name = "Hidden", isHidden = true)
        val units = Drink(name = "Units", category = DrinkCategory.UNITS, abv = 100.0, vessel = Vessel.SHOT, volumeMl = 10.0)
        for (drink in listOf(staropramen, hidden, units)) {
            database.rows().insert(drink)
            database.rows().insert(Favourite(drinkId = drink.id, vessel = drink.vessel, volumeMl = drink.volumeMl, price = drink.price))
        }

        assertEquals(listOf("Staropramen"), Today.observe(database, prefs()).first().tiles.map { it.drink.name })
    }
}
