package cc.blit.groglog

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.activity.ComponentActivity
import androidx.compose.ui.unit.dp
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Seed
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.ui.reports.HeartLines
import cc.blit.groglog.ui.reports.HeartReading
import cc.blit.groglog.ui.reports.MonthCard
import cc.blit.groglog.ui.reports.ProgressCard
import cc.blit.groglog.ui.reports.ReportsContent
import cc.blit.groglog.ui.reports.ReportsState
import cc.blit.groglog.ui.reports.SleepCard
import cc.blit.groglog.ui.reports.SummaryTiles
import cc.blit.groglog.ui.reports.WeekdayCard
import cc.blit.groglog.ui.reports.WeeksCard
import cc.blit.groglog.ui.reports.WeekCard
import cc.blit.groglog.ui.reports.runningRange
import cc.blit.groglog.ui.setup.HealthConnectStatus
import cc.blit.groglog.ui.setup.HealthSettingsContent
import cc.blit.groglog.ui.setup.HealthSettingsState
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.io.File
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Renders Reports from the demo log into the directory given as `-Pshots=DIR`, for checking by eye. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w412dp-h915dp-xxhdpi")
class ReportsShots {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private val directory = System.getProperty("groglog.shots").orEmpty()

    private fun demo(): ReportsState = runBlocking {
        val logbook = Logbook(database(), clock.copy(zone = java.time.ZoneId.systemDefault()))
        Seed.drinksIfNeeded(logbook)
        Seed.sample(logbook)
        val ledger = Ledger(logbook.rows.days(), logbook.clock)
        val goal = Goal(isEnabled = true, baselineWeekly = 210.0, start = Instant.now().minus(18, ChronoUnit.DAYS))
        val range = runningRange(ledger)
        ReportsState(ledger, goal, "GBP", Seed.nights(ledger), logbook.rows.entries(range.start.number, range.endInclusive.number))
    }

    /** Light, then dark, of one composition: a test can set its content only once. */
    private fun shoot(name: String, themes: List<Boolean> = listOf(false, true), content: @Composable () -> Unit) {
        var dark by mutableStateOf(themes.first())
        compose.setContent { GrogLogTheme(darkTheme = dark) { Surface(color = MaterialTheme.colorScheme.surface) { content() } } }
        for (theme in themes) {
            dark = theme
            compose.waitForIdle()
            val file = File(directory, "$name-${if (theme) "dark" else "light"}.png")
            file.parentFile?.mkdirs()
            // Drawn straight from the view: Compose's own capture waits for a frame Robolectric does not send.
            val view = compose.activity.window.decorView
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(android.graphics.Canvas(bitmap))
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
    }

    @Test fun screen() {
        assumeTrue(directory.isNotEmpty())
        val state = demo()
        shoot("screen") { ReportsContent(state, 12, {}, HeartReading.HRV, {}, {}) }
    }

    @Test @Config(qualifiers = "w412dp-h2400dp-xxhdpi")
    fun cards() {
        assumeTrue(directory.isNotEmpty())
        val state = demo()
        shoot("cards") {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                ProgressCard("Monthly progress", 35.0, 120, state.ledger, state.goal, state.nights, HeartLines.AVERAGED, HeartReading.RESTING, {}, {})
                SleepCard(state.ledger, state.nights)
                WeekCard(state.ledger, state.goal, state.entries)
                MonthCard(state.ledger, state.entries)
            }
        }
    }

    @Test @Config(qualifiers = "w412dp-h2000dp-xxhdpi")
    fun lower() {
        assumeTrue(directory.isNotEmpty())
        val state = demo()
        val stats = (12 downTo 0).map { state.ledger.week(state.ledger.clock.weekStart(state.ledger.today) - 7 * it, state.goal) }
        val days = stats.first().start..state.ledger.today
        shoot("lower") {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                WeeksCard(stats, state.nights, 12, {}, HeartReading.RESTING, {})
                SummaryTiles(state.ledger, stats, days, state.currency)
                WeekdayCard(state.ledger, days)
            }
        }
    }

    @Test @Config(qualifiers = "w412dp-h915dp-xxhdpi", fontScale = 2.0f)
    fun largeText() {
        assumeTrue(directory.isNotEmpty())
        val state = demo()
        shoot("large-text", listOf(false)) { ReportsContent(state, 12, {}, HeartReading.HRV, {}, {}) }
    }

    @Test fun healthSettings() {
        assumeTrue(directory.isNotEmpty())
        run {
            shoot("health-settings") {
                HealthSettingsContent(HealthSettingsState(HealthConnectStatus.AVAILABLE, copies = true, heart = true), {}, {}, {}, {}, {})
            }
        }
    }
}
