package cc.blit.groglog.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import cc.blit.groglog.ui.calendar.CalendarContent
import cc.blit.groglog.ui.calendar.sampleCalendarState
import cc.blit.groglog.ui.day.DayPage
import cc.blit.groglog.ui.day.sampleDayState
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Renders the Calendar and Day tabs to PNGs under build/shots, for checking against the iOS screens by eye. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "en-rGB-w411dp-h891dp-xxhdpi")
class DaysScreenshots {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private fun shoot(name: String, dark: Boolean = false, fontScale: Float? = null, content: @Composable () -> Unit) {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
                GrogLogTheme(darkTheme = dark, content = content)
            }
        }
        val file = File("build/shots/days/$name.png").apply { parentFile?.mkdirs() }
        compose.waitForIdle()
        val view = compose.activity.window.decorView
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(bitmap))
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Test fun day() = shoot("day") { DayPage(sampleDayState()) }

    @Test fun dayDark() = shoot("day-dark", dark = true) { DayPage(sampleDayState()) }

    @Test fun dryDay() = shoot("day-dry") { DayPage(sampleDayState(dry = true)) }

    @Test fun pastDay() = shoot("day-past") { DayPage(sampleDayState(sampleDayState().day - 1), onBack = {}) }

    @Test fun dayLargeText() = shoot("day-large-text", fontScale = 2f) { DayPage(sampleDayState()) }

    @Test fun calendar() = shoot("calendar") { CalendarContent(sampleCalendarState(), rememberLazyListState(), {}, { _, _ -> }) }

    @Test fun calendarDark() = shoot("calendar-dark", dark = true) { CalendarContent(sampleCalendarState(), rememberLazyListState(), {}, { _, _ -> }) }

    @Test fun calendarLargeText() = shoot("calendar-large-text", fontScale = 2f) { CalendarContent(sampleCalendarState(), rememberLazyListState(), {}, { _, _ -> }) }
}
