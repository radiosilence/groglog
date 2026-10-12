package cc.blit.groglog.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
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
 * A back stack per tab, as iOS's TabView keeps a navigation stack per tab: switching tabs leaves each where it was,
 * scrolled and paged as it was left, and pages pushed within it are there on return. Choosing the open tab again goes
 * back to its root, or, at the root, tells it so through `reselected`. Pages another tab opens, such as a drink's editor
 * from the Log, are pushed onto the open tab's stack, as iOS presents them as sheets over the tab.
 *
 * NavDisplay is given the other tabs' stacks beneath the open tab's, so their pages keep their saved state and
 * ViewModels, drafts included, while they are out of sight. Back at another tab's root goes to the Log, as Material
 * asks of a tab bar, and back at the Log's root leaves the app.
 *
 * Every page draws its own top bar, which takes the status bar's inset; the tab bar's is taken here.
 */
@Composable
private fun Root() {
    val stacks = tabs.associate { (tab) -> tab to rememberNavBackStack(tab) }
    var currentIndex by rememberSaveable { mutableIntStateOf(0) }
    val current = tabs[currentIndex].first
    val backStack = stacks.getValue(current)
    val reselected = remember { MutableSharedFlow<Tab>(extraBufferCapacity = 1) }
    val createDrink: (String) -> Unit = { backStack.add(SetupRoute.EditDrink(name = it)) }
    val editDrink: (Drink) -> Unit = { backStack.add(SetupRoute.EditDrink(it.id.toString())) }
    val setGoal: () -> Unit = { backStack.add(SetupRoute.Goal()) }
    fun select(tab: Tab) {
        if (tab == current) {
            val stack = stacks.getValue(tab)
            if (stack.size > 1) stack.subList(1, stack.size).clear() else reselected.tryEmit(tab)
        } else {
            currentIndex = tabs.indexOfFirst { it.first == tab }
        }
    }
    val destination by Destinations.pending.collectAsStateWithLifecycle()
    LaunchedEffect(destination) {
        if (destination == null) return@LaunchedEffect
        currentIndex = 0
        stacks.getValue(Tab.Log).let { if (it.size > 1) it.subList(1, it.size).clear() }
        Destinations.pending.compareAndSet(Destination.LOG, null)
    }
    // At large text sizes the labels would break mid-word, so the bar shows icons alone, each named for TalkBack.
    val compactLabels = LocalDensity.current.fontScale >= 1.5f
    Scaffold(
        bottomBar = {
            NavigationBar {
                for ((tab, label, icon) in tabs) {
                    val selected = current == tab
                    NavigationBarItem(
                        selected = selected,
                        onClick = { select(tab) },
                        icon = { Icon(icon, contentDescription = if (compactLabels) label else null) },
                        label = if (compactLabels) null else ({ Text(label, maxLines = 1, softWrap = false) }),
                        // The open tab's label in the ordinary ink, as on iOS: the theme's secondary is the dry teal,
                        // which means an alcohol-free day everywhere else.
                        colors = NavigationBarItemDefaults.colors(selectedTextColor = MaterialTheme.colorScheme.onSurface),
                    )
                }
            }
        },
    ) { padding ->
        val bottom = PaddingValues(bottom = padding.calculateBottomPadding())
        val modifier = Modifier.padding(bottom).consumeWindowInsets(bottom)
        val shown = tabs.map { it.first }.filter { it != current }.flatMap { stacks.getValue(it) } + backStack
        val activity = LocalActivity.current
        NavDisplay(
            backStack = shown,
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
        // Composed after NavDisplay so it takes back first at a tab's root, rather than showing the tab kept beneath.
        BackHandler(enabled = backStack.size == 1) { if (current == Tab.Log) activity?.finish() else currentIndex = 0 }
    }
}

/** Reselections of one tab. */
@Composable
private fun Flow<Tab>.of(tab: Tab): Flow<Unit> = remember(this, tab) { filter { it == tab }.map {} }
