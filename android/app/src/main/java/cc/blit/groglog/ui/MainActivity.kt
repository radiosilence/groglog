package cc.blit.groglog.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
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
import cc.blit.groglog.ui.day.DayScreen
import cc.blit.groglog.ui.log.LogScreen
import cc.blit.groglog.ui.reports.ReportsScreen
import cc.blit.groglog.ui.setup.SetupScreen
import cc.blit.groglog.ui.setup.setupEntries
import cc.blit.groglog.ui.theme.GrogLogTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
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
    Scaffold(
        bottomBar = {
            NavigationBar {
                for ((tab, label, icon) in tabs) {
                    NavigationBarItem(
                        selected = current == tab,
                        onClick = { backStack.select(tab) },
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
                entry<Tab.Calendar> { CalendarScreen(modifier) }
                entry<Tab.Day> { DayScreen(modifier) }
                entry<Tab.Reports> { ReportsScreen(modifier) }
                entry<Tab.Setup> { SetupScreen(modifier, onOpen = backStack::add) }
                setupEntries(modifier, backStack)
            },
        )
    }
}

private fun NavBackStack<NavKey>.select(tab: Tab) {
    if (lastOrNull() == tab) return
    clear()
    add(tab)
}
