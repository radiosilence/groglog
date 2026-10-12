package cc.blit.groglog.ui

import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import cc.blit.groglog.database
import cc.blit.groglog.prefs
import cc.blit.groglog.ui.day.DayPage
import cc.blit.groglog.ui.day.sampleDayState
import cc.blit.groglog.ui.setup.GoalPage
import cc.blit.groglog.ui.setup.GoalViewModel
import cc.blit.groglog.ui.shared.moneyEdit
import cc.blit.groglog.ui.shared.parseDecimal
import cc.blit.groglog.ui.theme.GrogLogTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowLooper

/** What QA found on a device, each pinned so it stays fixed. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "en-rGB-w411dp-h1600dp")
class RegressionTests {
    @get:Rule val compose = createComposeRule()

    @Test fun moneyShiftsDigitsInFromTheRightWhereverTheCursorIs() {
        assertEquals("1502", moneyEdit("150", "1502"))
        // The cursor at the start: the digit still goes on the end.
        assertEquals("1502", moneyEdit("150", "2150"))
        assertEquals("1502", moneyEdit("150", "1250"))
        // Backspace anywhere takes the last digit.
        assertEquals("15", moneyEdit("150", "15"))
        assertEquals("15", moneyEdit("150", "50"))
        assertEquals("", moneyEdit("1", ""))
        // Pasting a price adds its digits, whatever else it carries.
        assertEquals("450", moneyEdit("", "4.50"))
        assertEquals("450", moneyEdit("", "£4.50"))
        // Selecting all and typing replaces it.
        assertEquals("7", moneyEdit("150", "7"))
        assertEquals("", moneyEdit("", "0"))
        assertEquals("123456789", moneyEdit("123456789", "1234567890"))
    }

    @Test fun aCommaIsADecimalMark() {
        assertEquals(5.2, parseDecimal("5,2")!!, 0.0)
        assertEquals(5.2, parseDecimal("5.2")!!, 0.0)
        assertEquals(null, parseDecimal(","))
        assertEquals(null, parseDecimal(""))
    }

    @Test fun swipingOneDrinkAwayLeavesTheOthers() {
        var state by mutableStateOf(sampleDayState())
        val first = state.drinks.first()
        compose.setContent {
            GrogLogTheme {
                DayPage(state, onDelete = { pour -> state = state.copy(entries = state.entries.filter { it.pour.id != pour.id }) })
            }
        }
        val names = state.drinks.map { it.name }
        compose.onNode(hasScrollAction()).performScrollToNode(hasText(first.name))
        compose.onAllNodesWithText(first.name).onFirst().performTouchInput { swipeLeft() }
        compose.waitUntil(5_000) { state.drinks.size == names.size - 1 }
        compose.waitForIdle()
        for (name in names.drop(1).distinct()) {
            compose.onNode(hasScrollAction()).performScrollToNode(hasText(name))
            compose.onAllNodesWithText(name).onFirst().assertIsDisplayed()
        }
        assertEquals(names.drop(1), state.drinks.map { it.name })
    }

    @Test fun theGoalCanBeSavedOnceItLoads() {
        val model = GoalViewModel(database(), prefs())
        compose.setContent { GrogLogTheme { GoalPage(model, {}, {}) } }
        compose.waitUntil(5_000) {
            ShadowLooper.idleMainLooper()
            model.draft.value != null
        }
        compose.onNodeWithText("Done").assertIsEnabled()
    }
}
