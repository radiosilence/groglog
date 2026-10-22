package cc.blit.groglog.ui.log

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasScrollToNodeAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.database
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.prefs
import cc.blit.groglog.ui.theme.GrogLogTheme
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLooper

/** The Log tab end to end, over an in-memory log: taps, undo, the options sheet and the units sheet. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h1600dp")
class LogScreenTests {
    @get:Rule val compose = createComposeRule()

    private lateinit var database: AppDatabase
    private lateinit var logbook: Logbook
    private lateinit var viewModel: LogViewModel
    private val lager = Drink(name = "Staropramen", category = DrinkCategory.BEER, abv = 5.0, vessel = Vessel.PINT, volumeMl = 568.0, price = 6.0)
    private val rioja = Drink(name = "Rioja", category = DrinkCategory.RED_WINE, abv = 13.5, vessel = Vessel.WINE_GLASS, volumeMl = 175.0, price = 7.0)

    @Before fun setUp() {
        database = database()
        val prefs = prefs()
        logbook = runBlocking { Logbook(database, prefs.current().clock) }
        runBlocking {
            logbook.add(lager)
            logbook.add(rioja)
            val units = logbook.unitsDrink()
            logbook.pin(Serve(units))
        }
        viewModel = LogViewModel(database.queries(), prefs, { logbook })
        compose.setContent { GrogLogTheme { LogScreen(viewModel = viewModel) } }
        compose.waitUntilAtLeastOneExists(hasContentDescription("Staropramen"))
    }

    private fun pours() = runBlocking { database.rows().pours() }

    /** Waits on what the screen observes, running the main looper the view model's work is posted to. */
    private fun waitFor(condition: (LogState) -> Boolean) = compose.waitUntil(5_000) {
        ShadowLooper.idleMainLooper()
        viewModel.state.value?.let(condition) == true
    }

    private fun waitForPours(count: Int) = waitFor { it.pours.size == count }

    private fun tileOrder() = viewModel.state.value!!.tiles.map { it.drink.name }

    @Test fun aTapLogsOneNowAndCountsIt() {
        compose.onNodeWithContentDescription("Staropramen").performClick()
        waitForPours(1)
        assertEquals(lager.id, pours().single().drinkId)
        compose.waitUntilAtLeastOneExists(hasStateContaining("1 logged"))
        compose.waitUntilAtLeastOneExists(hasText("1 drink · "))
    }

    @Test fun theSnackbarUndoesTheTap() {
        compose.onNodeWithContentDescription("Staropramen").performClick()
        waitForPours(1)
        compose.waitUntilAtLeastOneExists(hasText("Undo"))
        compose.onNodeWithText("Undo").performClick()
        waitForPours(0)
    }

    @Test fun theSnackbarUndoesOnlyTheRoundItNamed() {
        compose.onNodeWithContentDescription("Staropramen").performClick()
        waitForPours(1)
        compose.waitUntilAtLeastOneExists(hasText("Undo"))
        // Logged elsewhere, as a widget would, after the snackbar appeared.
        runBlocking { logbook.log(Serve(rioja), listOf(java.time.Instant.now())) }
        waitForPours(2)
        compose.onNodeWithText("Undo").performClick()
        waitForPours(1)
        assertEquals(rioja.id, pours().single().drinkId)
    }

    @Test fun theBarsUndoPutsTheSnackbarAway() {
        compose.onNodeWithContentDescription("Staropramen").performClick()
        waitForPours(1)
        compose.waitUntilAtLeastOneExists(hasText("Undo"))
        compose.onNodeWithContentDescription("Undo last drink").performClick()
        waitForPours(0)
        compose.waitUntilDoesNotExist(hasText("Undo"))
    }

    @Test fun theBarUndoesTheLastDrink() {
        compose.onNodeWithContentDescription("Rioja").performClick()
        compose.onNodeWithContentDescription("Staropramen").performClick()
        waitForPours(2)
        compose.onNodeWithContentDescription("Undo last drink").performClick()
        waitForPours(1)
        assertEquals(rioja.id, pours().single().drinkId)
    }

    @Test fun aTapNeverReshufflesTheGrid() {
        waitFor { true }
        val before = tileOrder()
        compose.onNodeWithContentDescription("Rioja").performClick()
        waitForPours(1)
        compose.waitForIdle()
        assertEquals(before, tileOrder())

        // Coming back to the screen takes the new order.
        compose.runOnIdle { viewModel.appeared() }
        waitFor { it.tiles.first().drink.name == "Rioja" }
    }

    @Test fun nothingLoggedOffersAnAlcoholFreeDay() {
        compose.onNodeWithText("Alcohol-free").performClick()
        waitFor { it.ledger.status(it.day) == DayStatus.ALCOHOL_FREE }
        compose.waitUntilAtLeastOneExists(hasText("Undo"))
    }

    @Test fun longPressOpensTheOptionsAndLogsARound() {
        compose.onNodeWithContentDescription("Staropramen").performTouchInput { longClick() }
        compose.waitUntilAtLeastOneExists(hasText("Which one?"))
        compose.onNodeWithContentDescription("More").performClick()
        compose.onNodeWithContentDescription("More").performClick()
        compose.waitUntilAtLeastOneExists(hasText("How many: 3"))
        compose.onNode(hasText("Log 3 ·", substring = true) and hasClickAction()).performClick()
        waitForPours(3)
        assertEquals(setOf(lager.id), pours().map { it.drinkId }.toSet())

        // The snackbar takes the whole round back.
        compose.waitUntilAtLeastOneExists(hasText("Undo"))
        compose.onNodeWithText("Undo").performClick()
        waitForPours(0)
    }

    @Test fun theOptionsLogAtTheRoundsOwnStrength() {
        compose.onNodeWithContentDescription("Staropramen").performTouchInput { longClick() }
        compose.waitUntilAtLeastOneExists(hasText("Which one?"))
        compose.onNodeWithContentDescription("Strength").performTextClearance()
        compose.onNodeWithContentDescription("Strength").performTextInput("5.2")
        compose.onNode(hasText("Log ·", substring = true) and hasClickAction()).performClick()
        waitForPours(1)
        assertEquals(5.2, pours().single().abvOverride)
        assertEquals(5.0, runBlocking { database.rows().drink(lager.id) }!!.abv, 0.0)
    }

    @Test fun aStarPinsTheChoiceAtThisSize() {
        compose.onNodeWithContentDescription("Staropramen").performTouchInput { longClick() }
        compose.waitUntilAtLeastOneExists(hasText("Which one?"))
        compose.onNodeWithText("Half").performClick()
        compose.onAllNodes(hasContentDescription("Add to Log grid"))[0].performClick()
        waitFor { state -> state.favourites.any { it.drink.id == lager.id && it.favourite.vessel == Vessel.HALF } }
    }

    @Test fun theUnitsTileAsksForAnAmount() {
        // Units ends the grid, after the generic drinks.
        compose.onNode(hasScrollToNodeAction()).performScrollToNode(hasContentDescription("Units"))
        compose.onNodeWithContentDescription("Units").performClick()
        compose.waitUntilAtLeastOneExists(hasText("units"))
        compose.onNode(hasContentDescription("Units") and hasSetTextAction()).performTextInput("3.5")
        compose.onNode(hasText("Log") and hasClickAction()).performClick()
        waitForPours(1)
        assertEquals(35.0, pours().single().volumeMl, 0.0)
    }

    @Test fun aCataloguePickIsAdoptedAndLogged() {
        compose.onNodeWithContentDescription("Search drinks").performTextInput("guinness")
        compose.waitUntilAtLeastOneExists(hasText("UK drinks"))
        val item = viewModel.state.value!!.catalog.first()
        compose.onAllNodes(hasContentDescription(item.name))[0].performClick()
        waitForPours(1)
        assertEquals(item.name, runBlocking { database.rows().drink(pours().single().drinkId) }!!.name)
        compose.waitUntil { viewModel.search.isEmpty() }
    }

    @Test fun noMatchesSaysSo() {
        compose.onNodeWithContentDescription("Search drinks").performTextInput("zzzz")
        compose.waitUntilAtLeastOneExists(hasText("No matches for “zzzz”"))
    }
}

private fun hasStateContaining(text: String) = SemanticsMatcher("state contains $text") {
    it.config.getOrNull(SemanticsProperties.StateDescription)?.contains(text) == true
}
