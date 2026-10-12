package cc.blit.groglog.ui

import androidx.compose.foundation.text.input.setTextAndPlaceCursorAtEnd
import androidx.compose.material3.Text
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performTouchInput
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.database
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.prefs
import cc.blit.groglog.ui.log.LogScreen
import cc.blit.groglog.ui.log.LogViewModel
import cc.blit.groglog.ui.setup.DrinkEditorViewModel
import cc.blit.groglog.ui.setup.GoalViewModel
import cc.blit.groglog.ui.theme.GrogLogTheme
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLooper

/**
 * Drafts outlive their page leaving the screen and the process stopping: a ViewModel made again over the same saved
 * state, as Android does on return, comes back with what was typed rather than what the database holds.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h1600dp")
class DraftTests {
    @get:Rule val compose = createComposeRule()

    /** Lets the ViewModel see a typed change and keep it, as a frame would. */
    private fun settle(condition: () -> Boolean) = runBlocking {
        withTimeout(5_000) {
            while (!condition()) {
                Snapshot.sendApplyNotifications()
                ShadowLooper.idleMainLooper()
                kotlinx.coroutines.delay(10)
            }
        }
    }

    @Test fun aDrinksDraftComesBack() {
        val database = database()
        val prefs = prefs()
        val saved = SavedStateHandle()
        val first = DrinkEditorViewModel(database, prefs, null, "Hep", saved)
        settle { first.draft.value != null }
        first.name.setTextAndPlaceCursorAtEnd("Hepcat")
        first.setCategory(DrinkCategory.STOUT)
        settle { saved.get<String>("name") == "Hepcat" && saved.get<String>("category") == DrinkCategory.STOUT.name }

        val again = DrinkEditorViewModel(database, prefs, null, "Hep", saved)
        settle { again.draft.value != null }
        assertEquals("Hepcat", again.name.text.toString())
        assertEquals(DrinkCategory.STOUT, again.draft.value!!.category)
    }

    @Test fun aGoalsDraftComesBack() {
        val database = database()
        val prefs = prefs()
        val saved = SavedStateHandle()
        val first = GoalViewModel(database, prefs, saved)
        settle { first.draft.value != null }
        first.from.setTextAndPlaceCursorAtEnd("30")
        settle { saved.get<String>("from") == "30" }

        val again = GoalViewModel(database, prefs, saved)
        settle { again.draft.value != null }
        assertEquals("30", again.from.text.toString())
    }

    @Test fun theLogsSearchComesBack() {
        val saved = SavedStateHandle()
        val first = LogViewModel(database().queries(), prefs(), { error("unused") }, saved = saved)
        first.search = "rioja"
        assertEquals("rioja", LogViewModel(database().queries(), prefs(), { error("unused") }, saved = saved).search)
    }

    /** A page's ViewModel can be given its saved state inside the app's navigation, as the editors are. */
    @Test fun aPushedPageGetsItsSavedState() {
        compose.setContent {
            val stack = rememberNavBackStack(Tab.Log)
            NavDisplay(
                backStack = stack,
                entryDecorators = listOf(rememberSaveableStateHolderNavEntryDecorator(), rememberViewModelStoreNavEntryDecorator()),
                entryProvider = entryProvider {
                    entry<Tab.Log> {
                        val page = savedViewModel { _, saved -> SavedPage(saved) }
                        Text(if (page.saved.keys().isEmpty()) "fresh" else "restored")
                    }
                },
            )
        }
        compose.waitUntilAtLeastOneExists(hasText("fresh"))
    }

    @Test fun theOptionsSheetComesBackAfterRestore() {
        val restoration = StateRestorationTester(compose)
        val database = database()
        val prefs = prefs()
        val lager = Drink(name = "Staropramen", category = DrinkCategory.BEER, abv = 5.0, vessel = Vessel.PINT, volumeMl = 568.0, price = 6.0)
        val logbook = runBlocking { Logbook(database, prefs.current().clock).also { it.add(lager) } }
        val model = LogViewModel(database.queries(), prefs, { logbook })
        restoration.setContent { GrogLogTheme { LogScreen(viewModel = model) } }
        compose.waitUntilAtLeastOneExists(hasContentDescription("Staropramen"))
        compose.onNodeWithContentDescription("Staropramen").performTouchInput { longClick() }
        compose.waitUntilAtLeastOneExists(hasText("Which one?"))

        restoration.emulateSavedInstanceStateRestore()
        compose.waitUntilAtLeastOneExists(hasText("Which one?"), 5_000)
    }
}

class SavedPage(val saved: SavedStateHandle) : ViewModel()
