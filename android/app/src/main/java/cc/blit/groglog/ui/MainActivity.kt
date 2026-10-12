package cc.blit.groglog.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import cc.blit.groglog.container
import cc.blit.groglog.ui.calendar.CalendarScreen
import cc.blit.groglog.ui.day.DayScreen
import cc.blit.groglog.ui.log.LogScreen
import cc.blit.groglog.ui.reports.ReportsScreen
import cc.blit.groglog.ui.setup.SetupScreen
import cc.blit.groglog.ui.theme.GrogLogTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val dynamicColor = container.prefs.dynamicColor
        setContent {
            val dynamic by dynamicColor.collectAsStateWithLifecycle(false)
            GrogLogTheme(dynamicColor = dynamic) { Root() }
        }
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
    Scaffold(
        bottomBar = {
            NavigationBar {
                for (each in Tab.entries) {
                    NavigationBarItem(
                        selected = tab == each,
                        onClick = { tab = each },
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
            Tab.CALENDAR -> CalendarScreen(modifier)
            Tab.DAY -> DayScreen(modifier)
            Tab.REPORTS -> ReportsScreen(modifier)
            Tab.SETUP -> SetupScreen(modifier)
        }
    }
}
