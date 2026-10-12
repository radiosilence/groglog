package cc.blit.groglog.ui.log

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Seed
import cc.blit.groglog.database
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.prefs
import cc.blit.groglog.ui.shared.DrinkGlyph
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.io.File
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowLooper

/**
 * Renders the Log tab over sample data into `$SHOTS_DIR`, for looking at against the iOS screens. Skipped unless the
 * variable is set, since the pictures are for a person to judge rather than a test to compare.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xhdpi")
class LogScreenshots {
    @get:Rule val compose = createComposeRule()

    private val out = System.getenv("SHOTS_DIR")?.let(::File)

    private fun viewModel(): LogViewModel {
        val database = database()
        val prefs = prefs()
        val logbook = runBlocking { Logbook(database, prefs.current().clock) }
        runBlocking {
            Seed.drinksIfNeeded(logbook)
            Seed.sample(logbook, days = 30)
            val now = Instant.now()
            val grid = cc.blit.groglog.data.Serves.grid(database)
            logbook.log(grid.first { it.drink.name == "Gipsy Hill Hepcat" }, listOf(now.minusSeconds(5400), now.minusSeconds(3000)))
            logbook.log(grid.first { it.drink.name == "Rioja" }, listOf(now.minusSeconds(600)))
        }
        return LogViewModel(database.queries(), prefs, { logbook })
    }

    /**
     * Draws every window, the activity's and any sheet's over it, into one picture. Compose's own capture waits on the
     * main thread for a frame, which under Robolectric is the thread doing the waiting.
     */
    private fun save(name: String) {
        val dir = out ?: return
        dir.mkdirs()
        compose.waitForIdle()
        val global = Class.forName("android.view.WindowManagerGlobal")
        val instance = global.getMethod("getInstance").invoke(null)
        @Suppress("UNCHECKED_CAST")
        val views = global.getDeclaredField("mViews").apply { isAccessible = true }.get(instance) as List<View>
        val base = views.first()
        val bitmap = Bitmap.createBitmap(base.width, base.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        for (view in views) {
            val at = IntArray(2).also(view::getLocationOnScreen)
            canvas.save()
            canvas.translate(at[0].toFloat(), at[1].toFloat())
            view.draw(canvas)
            canvas.restore()
        }
        File(dir, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun show(dark: Boolean = false, fontScale: Float = 1f): LogViewModel {
        assumeTrue(out != null)
        val viewModel = viewModel()
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                GrogLogTheme(darkTheme = dark) { LogScreen(viewModel = viewModel) }
            }
        }
        compose.waitUntil(5_000) {
            ShadowLooper.idleMainLooper()
            viewModel.state.value?.pours?.size == 3
        }
        return viewModel
    }

    @Test fun light() {
        show()
        save("log-light")
    }

    @Test fun dark() {
        show(dark = true)
        save("log-dark")
    }

    @Test fun largeText() {
        show(fontScale = 2f)
        save("log-large-text")
    }

    @Test fun search() {
        show()
        compose.onNodeWithContentDescription("Search drinks").performTextInput("guin")
        compose.waitUntilAtLeastOneExists(hasText("UK drinks"))
        save("log-search")
    }

    @Test fun options() {
        show()
        compose.onNodeWithContentDescription("Rioja").performTouchInput { longClick() }
        compose.waitUntilAtLeastOneExists(hasText("How many: 1"))
        compose.mainClock.advanceTimeBy(1_000)
        save("log-options")
    }

    @Test fun optionsDark() {
        show(dark = true)
        compose.onNodeWithContentDescription("Gipsy Hill Hepcat").performTouchInput { longClick() }
        compose.waitUntilAtLeastOneExists(hasText("How many: 1"))
        compose.mainClock.advanceTimeBy(1_000)
        save("log-options-dark")
    }

    @Test fun units() {
        show()
        compose.onNodeWithContentDescription("Units").performTouchInput { longClick() }
        compose.waitUntilAtLeastOneExists(hasContentDescription("Units"))
        compose.mainClock.advanceTimeBy(1_000)
        save("log-units")
    }

    @Test @Config(qualifiers = "w411dp-h1100dp-xhdpi")
    fun glyphs() {
        assumeTrue(out != null)
        compose.setContent {
            Column {
                for (dark in listOf(false, true)) {
                    GrogLogTheme(darkTheme = dark) {
                        Surface {
                            Column(Modifier.padding(8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                for (category in DrinkCategory.entries) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        for (vessel in Vessel.entries) DrinkGlyph(category, vessel, Modifier.size(34.dp))
                                    }
                                }
                                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    for (ml in listOf(330.0, 440.0, 500.0, 568.0)) DrinkGlyph(DrinkCategory.BEER, Vessel.CAN, Modifier.size(56.dp), ml)
                                    for (fill in listOf(0.2f, 0.6f)) DrinkGlyph(DrinkCategory.STOUT, Vessel.PINT, Modifier.size(56.dp), fill = fill)
                                }
                            }
                        }
                    }
                }
            }
        }
        save("glyphs")
    }
}
