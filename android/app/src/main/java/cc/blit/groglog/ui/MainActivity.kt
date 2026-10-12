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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
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
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Drink
import cc.blit.groglog.ui.calendar.CalendarScreen
import cc.blit.groglog.ui.day.CalendarDayScreen
import cc.blit.groglog.ui.day.DayScreen
import cc.blit.groglog.ui.log.LogScreen
import cc.blit.groglog.ui.reports.ReportsScreen
import cc.blit.groglog.ui.setup.SetupScreen
import cc.blit.groglog.ui.setup.setupEntries
import cc.blit.groglog.ui.theme.GrogLogTheme
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) Destinations.open(intent)
        addOnNewIntentListener(Destinations::open)
        val prefs = container.prefs
        setContent {
            val dynamicColour by prefs.dynamicColour.collectAsStateWithLifecycle(false)
            GrogLogTheme(dynamicColour) { Root() }
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
 * root, as the system's predictive back gesture shows; choosing the open tab again tells it so, through `reselected`.
 * Pages another tab opens, such as a drink's editor from the Log, are pushed onto the same stack, as iOS presents them
 * as sheets over the tab.
 *
 * Every page draws its own top bar, which takes the status bar's inset; the tab bar's is taken here.
 */
@Composable
private fun Root() {
    val backStack = rememberNavBackStack(Tab.Log)
    val current = backStack.filterIsInstance<Tab>().lastOrNull() ?: Tab.Log
    val reselected = remember { MutableSharedFlow<Tab>(extraBufferCapacity = 1) }
    val createDrink: (String) -> Unit = { backStack.add(SetupRoute.EditDrink(name = it)) }
    val editDrink: (Drink) -> Unit = { backStack.add(SetupRoute.EditDrink(it.id.toString())) }
    val setGoal: () -> Unit = { backStack.add(SetupRoute.Goal) }
    val destination by Destinations.pending.collectAsStateWithLifecycle()
    LaunchedEffect(destination) {
        if (destination == null) return@LaunchedEffect
        backStack.select(Tab.Log)
        Destinations.pending.compareAndSet(Destination.LOG, null)
    }
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
        val bottom = PaddingValues(bottom = padding.calculateBottomPadding())
        val modifier = Modifier.padding(bottom).consumeWindowInsets(bottom)
        NavDisplay(
            backStack = backStack,
            onBack = { backStack.removeLastOrNull() },
            entryDecorators = listOf(rememberSaveableStateHolderNavEntryDecorator(), rememberViewModelStoreNavEntryDecorator()),
            entryProvider = entryProvider {
                entry<Tab.Log> {
                    LogScreen(
                        modifier,
                        reselected.of(Tab.Log),
                        createDrink,
                        editDrink,
                        unitsRequested = destination == Destination.UNITS,
                        onUnitsShown = { Destinations.pending.compareAndSet(Destination.UNITS, null) },
                    )
                }
                entry<Tab.Calendar> {
                    CalendarScreen(onOpen = { backStack.add(CalendarDay(it.number)) }, modifier = modifier, reselected = reselected.of(Tab.Calendar))
                }
                entry<CalendarDay> { key ->
                    CalendarDayScreen(
                        DayKey(key.day),
                        onBack = { backStack.removeLastOrNull() },
                        modifier = modifier,
                        onSetGoal = setGoal,
                        onCreateDrink = createDrink,
                        onEditDrink = editDrink,
                    )
                }
                entry<Tab.Day> { DayScreen(modifier, reselected.of(Tab.Day), setGoal, createDrink, editDrink) }
                entry<Tab.Reports> { ReportsScreen(modifier, reselected.of(Tab.Reports), setGoal) }
                entry<Tab.Setup> { SetupScreen(modifier, reselected.of(Tab.Setup), onOpen = backStack::add) }
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

/** Reselections of one tab. */
@Composable
private fun Flow<Tab>.of(tab: Tab): Flow<Unit> = remember(this, tab) { filter { it == tab }.map {} }
