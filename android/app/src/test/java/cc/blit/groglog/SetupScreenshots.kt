package cc.blit.groglog

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.test.core.app.ApplicationProvider
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Seed
import cc.blit.groglog.data.Settings
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Taper
import cc.blit.groglog.ui.setup.DrinkEditorViewModel
import cc.blit.groglog.ui.setup.DrinkGroups
import cc.blit.groglog.ui.setup.DrinkEditorPage
import cc.blit.groglog.ui.setup.DrinksPage
import cc.blit.groglog.ui.setup.GoalPage
import cc.blit.groglog.ui.setup.GoalViewModel
import cc.blit.groglog.ui.setup.GuidancePage
import cc.blit.groglog.ui.setup.SetupHome
import cc.blit.groglog.ui.theme.GrogLogTheme
import com.github.takahirom.roborazzi.captureRoboImage
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Setup's pages rendered headlessly, light and dark, for looking at rather than asserting on. They are written only when
 * recording: `./gradlew :app:testDebugUnitTest --tests '*SetupScreenshots*' -Proborazzi.test.record=true`, into
 * `app/build/outputs/roborazzi`.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "en-rGB-w411dp-h891dp-xxhdpi", sdk = [36])
class SetupScreenshots {
    private val out = "build/outputs/roborazzi/setup"

    @Before fun setUp() = Dispatchers.setMain(Dispatchers.Unconfined)

    @After fun tearDown() = Dispatchers.resetMain()

    private fun shoot(name: String, content: @Composable () -> Unit) {
        for (dark in listOf(false, true)) {
            captureRoboImage("$out/$name-${if (dark) "dark" else "light"}.png") {
                GrogLogTheme(darkTheme = dark) { Surface(Modifier.fillMaxSize()) { content() } }
            }
        }
    }

    /** A database with four months of sample drinking, and settings with a goal running. */
    private fun sample() = runBlocking {
        val database = database()
        val prefs = prefs()
        prefs.setGoal(Goal(isEnabled = true, taper = Taper.DYNAMIC, baselineWeekly = 26 * 7.0))
        val logbook = Logbook(database, prefs.current().clock)
        Seed.sample(logbook)
        Triple(database, prefs, Ledger(database.rows().days(), prefs.current().clock))
    }

    @Test fun setup() {
        val (_, prefs, ledger) = sample()
        val settings = runBlocking { prefs.current() }
        shoot("setup") {
            SetupHome(settings, ledger, version = "GrogLog 1.0 (1)", developer = true, isDemo = true)
        }
        shoot("setup-goal-off") {
            SetupHome(Settings(), ledger, version = "GrogLog 1.0 (1)", developer = false, isDemo = false)
        }
    }

    @Test fun drinks() {
        val (database, _, _) = sample()
        val drinks = runBlocking { database.queries().drinks().first() }
        val (generic, mine) = drinks.partition { it.isGeneric }
        val groups = DrinkGroups(mine.take(1).map { it.copy(abv = 4.9) } + mine.drop(1).take(1).map { it.copy(isHidden = true) }, mine.drop(2), generic)
        shoot("drinks") { DrinksPage(groups, {}, {}, {}, { _, _ -> }) }
    }

    @Test fun drinkEditor() {
        val (database, prefs, _) = sample()
        val drink = runBlocking { database.queries().drinks().first().first { it.name == "Gipsy Hill Hepcat" } }
        val existing = DrinkEditorViewModel(database, prefs, drink.id)
        val new = DrinkEditorViewModel(database, prefs, null)
        runBlocking {
            existing.draft.first { it != null }
            new.draft.first { it != null }
        }
        shoot("drink-editor") { DrinkEditorPage(existing, timesLogged = 40, onClose = {}) }
        new.strength.edit { replace(0, length, "") }
        shoot("drink-editor-new-invalid") { DrinkEditorPage(new, timesLogged = 0, onClose = {}) }
    }

    @Test fun goal() {
        val (database, prefs, _) = sample()
        val model = GoalViewModel(database, prefs)
        runBlocking {
            model.draft.first { it != null }
            model.ledger.first { it != null }
        }
        shoot("goal") { GoalPage(model, {}, {}) }
        model.setTaper(Taper.LINEAR)
        shoot("goal-linear") { GoalPage(model, {}, {}) }
        shoot("guidance") { GuidancePage {} }
    }

    @Test fun icon() {
        if (System.getProperty("roborazzi.test.record") != "true") return
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val icon = ContextCompat.getDrawable(context, R.mipmap.ic_launcher)!!
        val mono = ContextCompat.getDrawable(context, R.drawable.ic_launcher_monochrome)!!
        for ((name, drawable) in listOf("icon" to icon, "icon-monochrome" to mono)) {
            val bitmap = Bitmap.createBitmap(432, 432, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, 432, 432)
            drawable.draw(Canvas(bitmap))
            File(out).mkdirs()
            File(out, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
    }
}
