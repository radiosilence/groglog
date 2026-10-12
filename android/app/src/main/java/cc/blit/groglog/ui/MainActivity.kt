package cc.blit.groglog.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import cc.blit.groglog.ui.calendar.CalendarScreen
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
        setContent { GrogLogTheme { Root() } }
    }
}

private enum class Tab(val label: String, val icon: ImageVector) {
    LOG("Log", Icons.Filled.AddCircle),
    CALENDAR("Calendar", Icons.Filled.DateRange),
    DAY("Day", Icons.Filled.Info),
    REPORTS("Reports", Icons.AutoMirrored.Filled.List),
    SETUP("Setup", Icons.Filled.Settings),
}

@Composable
private fun Root() {
    var tab by rememberSaveable { mutableStateOf(Tab.LOG) }
    val reselected = remember { MutableSharedFlow<Tab>(extraBufferCapacity = 1) }
    Scaffold(
        bottomBar = {
            NavigationBar {
                for (each in Tab.entries) {
                    NavigationBarItem(
                        selected = tab == each,
                        onClick = { if (tab == each) reselected.tryEmit(each) else tab = each },
                        icon = { Icon(each.icon, contentDescription = null) },
                        label = { Text(each.label) },
                    )
                }
            }
        },
    ) { padding ->
        val modifier = Modifier.padding(padding)
        when (tab) {
            Tab.LOG -> LogScreen(modifier)
            // These draw their own top bars under the status bar, so they take only the bottom of the padding.
            Tab.CALENDAR -> CalendarScreen(padding.bottomOnly(), remember { reselected.filter { it == Tab.CALENDAR }.map {} }, onSetGoal = { tab = Tab.SETUP })
            Tab.DAY -> DayScreen(padding.bottomOnly(), remember { reselected.filter { it == Tab.DAY }.map {} }, onSetGoal = { tab = Tab.SETUP })
            Tab.REPORTS -> ReportsScreen(modifier)
            Tab.SETUP -> SetupScreen(modifier)
        }
    }
}

private fun PaddingValues.bottomOnly(): Modifier {
    val bottom = PaddingValues(bottom = calculateBottomPadding())
    return Modifier.padding(bottom).consumeWindowInsets(bottom)
}
