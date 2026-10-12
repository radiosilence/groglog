package cc.blit.groglog.ui.reports

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import cc.blit.groglog.container
import androidx.compose.ui.tooling.preview.Preview
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Night
import cc.blit.groglog.model.Nights
import cc.blit.groglog.model.Sleep
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Weekly and monthly progress, sleep, this week and month against earlier ones, the weekly bars, and the summary.
 * `onSetGoal` takes the reader to where the goal is set.
 */
@Composable
fun ReportsScreen(modifier: Modifier = Modifier, onSetGoal: () -> Unit = {}) {
    val context = LocalContext.current
    val model = viewModel { ReportsViewModel(context.container) }
    val state by model.state.collectAsStateWithLifecycle()
    val weeks by model.weeks.collectAsStateWithLifecycle()
    val shownHeart by model.shownHeart.collectAsStateWithLifecycle()
    LifecycleResumeEffect(model) {
        model.resume()
        onPauseOrDispose {}
    }
    ReportsContent(state, weeks, model::showWeeks, shownHeart, model::showHeart, onSetGoal, modifier)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportsContent(
    state: ReportsState?,
    weeks: Int,
    onWeeks: (Int) -> Unit,
    shownHeart: HeartReading,
    onShowHeart: (HeartReading) -> Unit,
    onSetGoal: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    Scaffold(
        modifier = modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = { Text("Reports") },
                actions = {
                    TextButton(onClick = onSetGoal) {
                        Icon(ReportIcons.target, contentDescription = null)
                        Text(if (state?.goal?.isEnabled == true) "Goal" else "Set a goal", modifier = Modifier.padding(start = 8.dp))
                    }
                },
                scrollBehavior = scroll,
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
        // The app bar takes the status bar; whoever places this takes the navigation bar.
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        if (state == null) {
            Box(Modifier.fillMaxSize().padding(padding))
            return@Scaffold
        }
        val ledger = state.ledger
        val today = ledger.today
        val clock = ledger.clock
        val thisWeek = clock.weekStart(today)
        val stats = remember(ledger, state.goal, state.nights.first, weeks) {
            // Back to the first heart reading as well, so the line carries on from before the log began.
            val earliest = listOfNotNull(ledger.firstDay, state.nights.first).minOrNull() ?: today
            val firstWeek = minOf(clock.weekStart(earliest), thisWeek - 7 * (weeks - 1))
            (firstWeek.number..thisWeek.number step 7).map { ledger.week(DayKey(it), state.goal) }
        }
        val shown = stats.takeLast(weeks)
        val days = minOf(maxOf(shown.first().start, ledger.firstDay ?: today), today)..today
        val hasSleep = state.nights.byDay.values.any { it.sleep != null }

        LazyColumn(
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding() + 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item("weekly progress") {
                ProgressCard("Weekly progress", 10.0, 60, ledger, state.goal, state.nights, HeartLines.NIGHTLY, shownHeart, onShowHeart, onSetGoal)
            }
            item("monthly progress") {
                ProgressCard("Monthly progress", 35.0, 120, ledger, state.goal, state.nights, HeartLines.AVERAGED, shownHeart, onShowHeart, onSetGoal)
            }
            if (hasSleep) item("sleep") { SleepCard(ledger, state.nights) }
            item("week") { WeekCard(ledger, state.goal, state.entries) }
            item("month") { MonthCard(ledger, state.entries) }
            item("weeks") { WeeksCard(stats, state.nights, weeks, onWeeks, shownHeart, onShowHeart) }
            item("summary") { SummaryTiles(ledger, shown, days, state.currency) }
            item("weekdays") { WeekdayCard(ledger, days) }
        }
    }
}

/** A month of steady drinking with a taper begun a fortnight ago, and a watch's readings. */
private fun previewState(): ReportsState {
    val clock = DayClock(5)
    val today = clock.today
    val days = (1..40).map { offset ->
        val day = today - offset
        if (offset % 6 == 0) Day(day.number, isAlcoholFree = true) else Day(day.number, units = 8.0 + (offset * 7) % 9, kcal = 600.0, cost = 18.0, count = 4)
    }
    val nights = Nights((1..40).associate { (today - it) to Night(hrv = 50.0 + it % 7, restingHR = 56.0 - it % 4, sleepingHR = 52.0, sleep = Sleep(deep = 5000.0, core = 14000.0, rem = 6000.0, awake = 1500.0)) })
    val goal = Goal(isEnabled = true, baselineWeekly = 84.0, start = Instant.now().minus(14, ChronoUnit.DAYS))
    return ReportsState(Ledger(days, clock), goal, "GBP", nights, emptyList())
}

@Preview
@Composable
private fun ReportsPreview() {
    GrogLogTheme { ReportsContent(previewState(), 12, {}, HeartReading.HRV, {}, {}) }
}

@Preview
@Composable
private fun ReportsDarkPreview() {
    GrogLogTheme(darkTheme = true) { ReportsContent(previewState(), 12, {}, HeartReading.RESTING, {}, {}) }
}
