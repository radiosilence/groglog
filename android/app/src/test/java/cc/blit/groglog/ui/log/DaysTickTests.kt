package cc.blit.groglog.ui.log

import cc.blit.groglog.model.DayClock
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

/** The Log picker's today moves on at the day's end without anything being logged. */
@OptIn(ExperimentalCoroutinesApi::class)
class DaysTickTests {
    @Test fun todayMovesOnAtTheDayEnd() = runTest {
        val clock = DayClock(5, ZoneId.of("Europe/London"))
        val start = LocalDateTime.of(2026, 10, 12, 23, 0).atZone(clock.zone).toInstant()
        val now = { start.plusMillis(testScheduler.currentTime) }
        val days = LogViewModel.days(clock, now).take(2).toList()
        assertEquals(listOf(clock.day(start), clock.day(start) + 1), days)
        // Six hours on, at 5am, not a minute's polling later.
        val end = Instant.ofEpochMilli(start.toEpochMilli() + testScheduler.currentTime)
        assertEquals(clock.end(clock.day(start)).toEpochMilli() + 1, end.toEpochMilli())
    }
}
