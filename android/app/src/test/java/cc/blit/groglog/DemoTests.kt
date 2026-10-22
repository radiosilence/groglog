package cc.blit.groglog

import android.content.Context
import androidx.core.content.edit
import androidx.test.core.app.ApplicationProvider
import cc.blit.groglog.data.HealthSwitches
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Seed
import cc.blit.groglog.data.settingsStore
import cc.blit.groglog.model.Ledger
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Demo mode keeps to itself, as iOS's `Store.demo()` does. */
@RunWith(RobolectricTestRunner::class)
class DemoTests {
    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun demo(on: Boolean) = context.getSharedPreferences("developer", Context.MODE_PRIVATE).edit(commit = true) { putBoolean("demoMode", on) }

    @Before fun on() = demo(true)

    @After fun off() = demo(false)

    @Test fun startsWithTheGoalIosDemoSets() = runBlocking {
        val goal = Prefs.demo().current().goal
        assertTrue(goal.isEnabled)
        assertEquals(10.0, goal.reductionPercent, 0.0)
        assertEquals(7, goal.periodDays)
    }

    @Test fun itsSettingsNeverReachTheRealOnes() = runBlocking {
        val container = AppContainer(context)
        assertTrue(container.isDemo)
        val real = Prefs(context.settingsStore)
        val before = real.current()
        container.prefs.setCurrency(if (before.currency == "JPY") "EUR" else "JPY")
        container.prefs.setRolloverHour((before.rolloverHour + 1) % 24)
        assertNotEquals(before.currency, container.prefs.current().currency)
        assertEquals(before.currency, real.current().currency)
        assertEquals(before.rolloverHour, real.current().rolloverHour)
    }

    @Test fun widgetsAndShortcutsKeepToTheRealLog() {
        val container = AppContainer(context)
        assertNotSame(container.database, container.liveDatabase)
        assertNotSame(container.prefs, container.livePrefs)
    }

    @Test fun neverAsksHealthConnect() = runBlocking {
        val container = AppContainer(context)
        container.prefs.setHealth(HealthSwitches(copies = true, heart = true, sleep = true))
        val clock = container.prefs.current().clock
        // Nothing to write to or read from, whatever the switches say.
        container.health.mirror(null)
        assertTrue(container.health.nights(clock, heart = true, sleep = true).byDay.isEmpty())
        assertEquals(null, container.health.granted())
    }

    @Test fun samplesNightsThatFollowTheLog() = runBlocking {
        val (logbook, _) = logbook()
        Seed.sample(logbook)
        val ledger = Ledger(logbook.rows.days(), logbook.clock)
        val nights = Seed.nights(ledger)
        assertTrue(nights.byDay.size > 60)
        // The few weeks the watch stopped syncing.
        assertTrue(((ledger.today - 75)..(ledger.today - 40)).none { it in nights.byDay })
    }
}
