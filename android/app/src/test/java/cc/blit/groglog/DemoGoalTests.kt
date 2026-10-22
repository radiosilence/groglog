package cc.blit.groglog

import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Seed
import cc.blit.groglog.model.Ledger
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Demo mode shows a taper under way: a budget today, below where it started and not yet run down to nothing. */
@RunWith(RobolectricTestRunner::class)
class DemoGoalTests {
    @Test fun theDemoHasALiveBudgetToday() = runBlocking {
        val prefs = Prefs.demo()
        val database = database()
        val logbook = Logbook(database, prefs.current().clock)
        Seed.sample(logbook)
        val ledger = Ledger(database.rows().days(), logbook.clock)
        val goal = Seed.demoGoal(ledger, prefs.current().goal)

        val budget = ledger.dailyBudget(ledger.today, goal)!!
        assertTrue("Budget today is $budget", budget > 0)
        assertTrue("Budget today $budget is not below the starting ${goal.baselineWeekly / 7}", budget < goal.baselineWeekly / 7)
    }
}
