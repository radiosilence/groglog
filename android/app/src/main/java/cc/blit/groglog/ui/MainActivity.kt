package cc.blit.groglog.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import cc.blit.groglog.container
import cc.blit.groglog.ui.calendar.CalendarScreen
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.ui.day.CalendarDayScreen
import cc.blit.groglog.ui.day.DayScreen
import cc.blit.groglog.ui.log.LogScreen
import cc.blit.groglog.ui.reports.ReportsScreen
import cc.blit.groglog.ui.setup.SetupScreen
import cc.blit.groglog.ui.theme.GrogLogTheme
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val prefs = container.prefs
        setContent {
            val settings by prefs.settings.collectAsStateWithLifecycle(null)
            GrogLogTheme(dynamicColour = settings?.dynamicColour == true) { Root() }
        }
    }
}

private val tabs: List<Triple<Tab, String, ImageVector>> = listOf(
    Triple(Tab.Log, "Log", Icons.Filled.AddCircle),
    Triple(Tab.Calendar, "Calendar", Icons.Filled.DateRange),
    Triple(Tab.Day, "Day", Icons.Filled.Info),
    Triple(Tab.Reports, "Reports", Icons.AutoMirrored.Filled.List),
    Triple(Tab.Setup, "Setup", Icons.Filled.Settings),
)

/**
 * One back stack, rooted at the open tab. Choosing a tab replaces the stack, so back leaves the app from any tab's
 * root, as the system's predictive back gesture shows.
 */
@Composable
private fun Root() {
    val backStack = rememberNavBackStack(Tab.Log)
    val current = backStack.filterIsInstance<Tab>().lastOrNull() ?: Tab.Log
    val reselected = remember { MutableSharedFlow<Tab>(extraBufferCapacity = 1) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                for ((tab, label, icon) in tabs) {
                    NavigationBarItem(
                        selected = current == tab,
                        onClick = { if (backStack.lastOrNull() == tab) reselected.tryEmit(tab) else backStack.select(tab) },
                        icon = { Icon(icon, contentDescription = null) },
                        label = { Text(label) },
                    )
                }
            }
        },
    ) { padding ->
        val modifier = Modifier.padding(padding)
        NavDisplay(
            backStack = backStack,
            onBack = { backStack.removeLastOrNull() },
            entryDecorators = listOf(rememberSaveableStateHolderNavEntryDecorator(), rememberViewModelStoreNavEntryDecorator()),
            entryProvider = entryProvider {
                entry<Tab.Log> { LogScreen(modifier) }
                // These draw their own top bars under the status bar, so they take only the bottom of the padding.
                entry<Tab.Calendar> {
                    CalendarScreen(
                        onOpen = { backStack.add(CalendarDay(it.number)) },
                        modifier = padding.bottomOnly(),
                        reselected = remember { reselected.filter { it == Tab.Calendar }.map {} },
                    )
                }
                entry<CalendarDay> { key ->
                    CalendarDayScreen(DayKey(key.day), onBack = { backStack.removeLastOrNull() }, modifier = padding.bottomOnly(), onSetGoal = { backStack.select(Tab.Setup) })
                }
                entry<Tab.Day> {
                    DayScreen(padding.bottomOnly(), remember { reselected.filter { it == Tab.Day }.map {} }, onSetGoal = { backStack.select(Tab.Setup) })
                }
                entry<Tab.Reports> { ReportsScreen(padding.bottomOnly(), onSetGoal = { backStack.select(Tab.Setup) }) }
                entry<Tab.Setup> { SetupScreen(modifier) }
            },
        )
    }
}

private fun NavBackStack<NavKey>.select(tab: Tab) {
    if (lastOrNull() == tab) return
    clear()
    add(tab)
}

private fun PaddingValues.bottomOnly(): Modifier {
    val bottom = PaddingValues(bottom = calculateBottomPadding())
    return Modifier.padding(bottom).consumeWindowInsets(bottom)
}
