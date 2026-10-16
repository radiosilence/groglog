package cc.blit.groglog.shortcut

import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import cc.blit.groglog.GrogLogApplication
import cc.blit.groglog.container
import cc.blit.groglog.data.Serves
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.shadows.ShadowLooper

@RunWith(RobolectricTestRunner::class)
class LogShortcutTests {
    @Test fun aRotationWhileTheCardShowsDoesNotLogAgain() = runBlocking {
        val app = ApplicationProvider.getApplicationContext<GrogLogApplication>()
        val database = app.container.liveDatabase
        // The container seeds the generic drinks in the background as it starts.
        val serve = withTimeout(10_000) {
            var first = Serves.grid(database).firstOrNull()
            while (first == null) {
                delay(50)
                first = Serves.grid(database).firstOrNull()
            }
            first
        }
        val scenario = ActivityScenario.launch<LogShortcutActivity>(LogShortcutActivity.intent(app, serve.id))
        withTimeout(10_000) {
            while (database.rows().pours().isEmpty()) {
                ShadowLooper.idleMainLooper()
                delay(50)
            }
        }
        scenario.recreate()
        repeat(10) {
            ShadowLooper.idleMainLooper()
            delay(50)
        }
        assertEquals(1, database.rows().pours().size)
        scenario.close()
    }
}
