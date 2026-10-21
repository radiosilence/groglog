package cc.blit.groglog.ui.log

import cc.blit.groglog.clock
import cc.blit.groglog.date
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Favourite
import cc.blit.groglog.model.FavouriteItem
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Vessel
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PickerTests {
    private val lager = Drink(name = "Staropramen", category = DrinkCategory.BEER, abv = 5.0, vessel = Vessel.PINT, volumeMl = 568.0, price = 6.0)
    private val rioja = Drink(name = "Rioja", category = DrinkCategory.RED_WINE, abv = 13.5, vessel = Vessel.WINE_GLASS, volumeMl = 175.0, price = 7.0)
    private val hidden = lager.copy(id = java.util.UUID.randomUUID(), name = "Old lager", isHidden = true)
    private val friday = DayKey.of(2026, 3, 6)

    private fun pinned(drink: Drink, order: Int, used: java.time.Instant? = null) =
        FavouriteItem(Favourite(drinkId = drink.id, vessel = drink.vessel, volumeMl = drink.volumeMl, price = drink.price, sortOrder = order, lastUsed = used), drink)

    private fun entry(drink: Drink, at: java.time.Instant) =
        Entry(Pour(drinkId = drink.id, timestamp = at, day = clock.day(at).number, vessel = drink.vessel, volumeMl = drink.volumeMl, price = drink.price), drink)

    @Test fun withoutRecencyTilesKeepFavouriteOrder() {
        val tiles = Picker.tiles("", listOf(pinned(lager, 0), pinned(rioja, 1)), listOf(lager, rioja), emptyList(), emptyMap(), Usual.none)
        assertEquals(listOf("Staropramen", "Rioja"), tiles.map { it.drink.name })
    }

    @Test fun theDaysDrinksComeFirstAndFavouritesKeepTheirPinnedOrder() {
        val favourites = listOf(pinned(lager, 0, used = date(2026, 3, 5, 21)), pinned(rioja, 1, used = date(2026, 3, 6, 21)))
        assertEquals(listOf("Staropramen", "Rioja"), Picker.tiles("", favourites, listOf(lager, rioja), emptyList(), emptyMap(), Usual.none).map { it.drink.name })

        val pours = listOf(entry(rioja, date(2026, 3, 6, 21)))
        val tiles = Picker.tiles("", favourites, listOf(lager, rioja), pours, Picker.recency(pours), Usual.none)
        assertEquals(listOf("Rioja", "Staropramen"), tiles.map { it.drink.name })
    }

    @Test fun usualDrinksFollowTheFavouritesAndGenericsComeLast() {
        val cider = lager.copy(id = java.util.UUID.randomUUID(), name = "Cider", category = DrinkCategory.CIDER, isGeneric = true, sortOrder = 100)
        val beer = lager.copy(id = java.util.UUID.randomUUID(), name = "Beer", isGeneric = true, sortOrder = 101)
        val drinks = listOf(beer, cider, lager, rioja)
        val fridays = (1L..4L).map { week -> entry(rioja, date(2026, 3, 6, 20).minus(Duration.ofDays(7 * week))).pour }
        val usual = Usual.of(fridays, drinks, clock, friday, date(2026, 3, 6, 20))
        val tiles = Picker.tiles("", listOf(pinned(lager, 0)), drinks, emptyList(), emptyMap(), usual)
        assertEquals(listOf("Staropramen", "Rioja", "Cider", "Beer"), tiles.map { it.drink.name })

        val searched = Picker.tiles("r", emptyList(), drinks, emptyList(), emptyMap(), usual)
        assertEquals("Rioja", searched.first().drink.name)
    }

    @Test fun aHiddenDrinkIsNeverUsual() {
        val fridays = (1L..4L).map { week -> entry(hidden, date(2026, 3, 6, 20).minus(Duration.ofDays(7 * week))).pour }
        assertTrue(Usual.of(fridays, listOf(hidden), clock, friday, date(2026, 3, 6, 20)).serves.isEmpty())
    }

    @Test fun aHiddenDrinkShowsOnlyOnTheDayItWasLogged() {
        val favourites = listOf(pinned(lager, 0), pinned(hidden, 1))
        assertEquals(listOf("Staropramen"), Picker.tiles("", favourites, listOf(lager, hidden), emptyList(), emptyMap(), Usual.none).map { it.drink.name })

        val pours = listOf(entry(hidden, date(2026, 3, 6, 20)))
        val tiles = Picker.tiles("", favourites, listOf(lager, hidden), pours, Picker.recency(pours), Usual.none)
        assertEquals(listOf("Old lager", "Staropramen"), tiles.map { it.drink.name })
    }

    @Test fun aDrinkLoggedInAnotherSizeGetsItsOwnTile() {
        val half = entry(lager, date(2026, 3, 6, 20)).let { it.copy(pour = it.pour.copy(vessel = Vessel.HALF, volumeMl = 284.0)) }
        val tiles = Picker.tiles("", listOf(pinned(lager, 0)), listOf(lager), listOf(half), emptyMap(), Usual.none)
        assertEquals(listOf(Vessel.PINT, Vessel.HALF), tiles.map { it.vessel })
    }

    @Test fun searchOffersEverySizeAtThePinnedPrice() {
        val favourite = pinned(lager, 0).let { it.copy(favourite = it.favourite.copy(price = 5.5)) }
        val tiles = Picker.tiles("staro", listOf(favourite), listOf(lager, rioja), emptyList(), emptyMap(), Usual.none)
        assertTrue(tiles.all { it.drink.id == lager.id })
        assertEquals(lager.sizes(cc.blit.groglog.model.ServeSize(Vessel.PINT, 568.0)).size, tiles.size)
        assertEquals(5.5, tiles.first { it.vessel == Vessel.PINT }.price, 0.0)
    }

    @Test fun searchFindsByTypeIgnoringAccents() {
        val rose = rioja.copy(id = java.util.UUID.randomUUID(), name = "Whispering Angel", category = DrinkCategory.ROSE)
        val tiles = Picker.tiles("rose", emptyList(), listOf(lager, rose), emptyList(), emptyMap(), Usual.none)
        assertTrue(tiles.isNotEmpty() && tiles.all { it.drink.name == "Whispering Angel" })
    }

    @Test fun theCatalogueLeavesOutBrandsAlreadyAdopted() {
        val all = Picker.catalogMatches("guinness", emptyList())
        assertTrue(all.isNotEmpty())
        val first = all.first()
        val adopted = Drink(name = first.name, category = first.category, abv = first.abv, vessel = first.vessel, volumeMl = first.volumeMl)
        assertTrue(Picker.catalogMatches("guinness", listOf(adopted)).none { it.name == first.name })
        assertTrue(Picker.catalogMatches("  ", emptyList()).isEmpty())
    }

    @Test fun choicesLeadWithThePressedDrinkThenGenericsThenTheCatalogue() {
        val beer = lager.copy(id = java.util.UUID.randomUUID(), name = "Beer", isGeneric = true, abv = 4.0)
        val choices = Picker.choices(lager, "", listOf(lager, beer, rioja, hidden))
        assertEquals("Staropramen", choices[0].name)
        assertEquals("Beer", choices[1].name)
        assertTrue(choices.none { it.name == "Rioja" || it.name == "Old lager" })
        assertTrue(choices.drop(2).all { it.brand != null && it.category == DrinkCategory.BEER })
    }

    @Test fun aRoundOnAPastDayIsTwentyMinutesApart() {
        val times = Picker.spreadTimes(date(2026, 3, 6, 20), 3, friday, clock, now = date(2026, 3, 10, 12))
        assertEquals(listOf(date(2026, 3, 6, 20), date(2026, 3, 6, 20, 20), date(2026, 3, 6, 20, 40)), times)
    }

    @Test fun aRoundNearTheDaysEndStaysInsideIt() {
        val times = Picker.spreadTimes(date(2026, 3, 7, 4, 30), 4, friday, clock, now = date(2026, 3, 10, 12))
        assertTrue(times.all { clock.day(it) == friday })
        assertTrue(Duration.between(times[0], times[1]) < Duration.ofMinutes(20))
    }

    @Test fun aRoundTodayRunsUpToNow() {
        val now = date(2026, 3, 6, 22)
        val times = Picker.spreadTimes(date(2026, 3, 6, 20), 5, friday, clock, now = now)
        assertEquals(date(2026, 3, 6, 20), times.first())
        assertEquals(now, times.last())
    }

    @Test fun oneIsLoggedAtTheChosenTime() {
        assertEquals(listOf(date(2026, 3, 6, 20)), Picker.spreadTimes(date(2026, 3, 6, 20), 1, friday, clock))
    }
}
