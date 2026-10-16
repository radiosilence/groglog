package cc.blit.groglog

import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.NutritionRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import cc.blit.groglog.data.HealthSwitches
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.health.Health
import cc.blit.groglog.ui.health.PolicyBlock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.SleepStage
import java.time.Instant
import java.time.ZoneOffset
import java.util.TimeZone
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** The calorie mirror: rewritten a day at a time, never doubled, never touching another app's records. */
@RunWith(RobolectricTestRunner::class)
class HealthMirrorTests {
    private val saturday = DayKey.of(2026, 9, 19)

    @Before fun london() = TimeZone.setDefault(TimeZone.getTimeZone("Europe/London"))

    private suspend fun setup(copies: Boolean = true, granted: Set<String> = Health.COPY): Triple<Health, Logbook, FakeHealthConnect> {
        val prefs = prefs()
        prefs.setHealth(HealthSwitches(copies = copies))
        val fake = FakeHealthConnect(granted)
        val (book, drink) = logbook()
        val logbook = Logbook(book.database, prefs.current().clock)
        logbook.log(Serve(drink), listOf(date(2026, 9, 19, 21), date(2026, 9, 20, 1), date(2026, 9, 20, 20)))
        return Triple(Health(book.database, prefs, { fake }), logbook, fake)
    }

    private fun FakeHealthConnect.kcal() = own.filterIsInstance<NutritionRecord>().map { it.startTime to it.energy!!.inKilocalories }

    @Test fun mirrorsEachDrinkAsItsCalories() = runBlocking {
        val (health, logbook, fake) = setup()
        health.mirror(null)
        val pint = rowsKcal(logbook)
        assertEquals(3, fake.own.size)
        assertTrue(fake.kcal().all { near(it.second, pint) })
        assertEquals("Beer", (fake.own[0] as NutritionRecord).name)
    }

    @Test fun aChangedDayIsRewrittenWithoutTouchingItsNeighbours() = runBlocking {
        val (health, logbook, fake) = setup()
        health.mirror(null)
        // The 1am pint is Saturday night's; deleting it and rewriting Saturday leaves Sunday's alone.
        val late = logbook.rows.entries(saturday.number, saturday.number).first { it.timestamp == date(2026, 9, 20, 1) }
        logbook.delete(late.pour)
        health.mirror(setOf(saturday))
        assertEquals(listOf(date(2026, 9, 19, 21), date(2026, 9, 20, 20)), fake.kcal().map { it.first }.sorted())
    }

    @Test fun aDrinkOnTheStrokeOfTheDayEndStaysInItsOwnDay() = runBlocking {
        val (health, logbook, fake) = setup()
        val drink = logbook.rows.drinks().first { it.name == "Beer" }
        // 4:59:59.999 is still Saturday night; the next day starts a millisecond later.
        logbook.log(Serve(drink), listOf(date(2026, 9, 20, 5).minusMillis(1)))
        health.mirror(null)
        health.mirror(setOf(saturday + 1))
        assertEquals(4, fake.own.size)
    }

    @Test fun concurrentRewritesOfADayDoNotDoubleIt() = runBlocking {
        val (health, _, fake) = setup()
        listOf(async { health.mirror(setOf(saturday)) }, async { health.mirror(setOf(saturday)) }).awaitAll()
        assertEquals(2, fake.own.size)
    }

    @Test fun anotherAppsRecordsAreLeftAlone() = runBlocking {
        val (health, _, fake) = setup()
        fake.others += NutritionRecord(
            startTime = date(2026, 9, 19, 22),
            startZoneOffset = ZoneOffset.UTC,
            endTime = date(2026, 9, 19, 22, 1),
            endZoneOffset = ZoneOffset.UTC,
            metadata = fake.other("com.example.food"),
            name = "Chips",
        )
        health.mirror(null)
        health.removeMirror()
        assertEquals(0, fake.own.size)
        assertEquals(1, fake.others.size)
    }

    @Test fun nothingIsWrittenWithCopyingOffOrWritingRefused() = runBlocking {
        val (off, _, offFake) = setup(copies = false)
        off.mirror(null)
        assertEquals(0, offFake.own.size)
        val (refused, _, refusedFake) = setup(granted = emptySet())
        refused.mirror(null)
        assertEquals(0, refusedFake.own.size)
    }

    @Test fun aDrinkWithNoCaloriesWritesNothing() {
        val drink = Drink(name = "Units", category = DrinkCategory.UNITS, abv = 0.0, vessel = Vessel.SHOT, volumeMl = 10.0)
        assertNull(Health.record(Entry(Pour(drinkId = drink.id, timestamp = Instant.now(), day = 0, vessel = Vessel.SHOT, volumeMl = 10.0, price = 0.0), drink)))
    }

    @Test fun everyWritePathAnnouncesTheDaysItChanged() = runBlocking {
        val (logbook, drink) = logbook()
        val heard = async { Logbook.changed.take(3).toList() }
        // Let the collector subscribe; nothing is buffered without one.
        repeat(5) { yield() }
        launch {
            logbook.log(Serve(drink), listOf(date(2026, 9, 19, 21)))
            logbook.undo(saturday)
            logbook.rebuild()
        }.join()
        assertEquals(listOf(setOf(saturday), setOf(saturday), null), heard.await())
    }

    private suspend fun rowsKcal(logbook: Logbook) = logbook.rows.entries().first().kcal
}

/** Reading heart and sleep back, filed under the drinking day each night followed. */
@RunWith(RobolectricTestRunner::class)
class HealthReadingTests {
    private val friday = DayKey.of(2026, 9, 18)

    @Before fun london() = TimeZone.setDefault(TimeZone.getTimeZone("Europe/London"))

    private suspend fun health(fake: FakeHealthConnect, heart: Boolean = true, sleep: Boolean = true): Pair<Health, Prefs> {
        val prefs = prefs()
        prefs.setHealth(HealthSwitches(heart = heart, sleep = sleep))
        return Health(database(), prefs, { fake }) to prefs
    }

    private fun session(fake: FakeHealthConnect, source: String, start: Instant, end: Instant, stages: List<Triple<Instant, Instant, Int>>) =
        SleepSessionRecord(start, ZoneOffset.UTC, end, ZoneOffset.UTC, fake.other(source), stages = stages.map { SleepSessionRecord.Stage(it.first, it.second, it.third) })

    private fun fake() = FakeHealthConnect(Health.HEART + Health.SLEEP)

    @Test fun stagesAreFiledUnderTheEveningBefore() = runBlocking {
        val fake = fake()
        fake.others += session(
            fake, "watch", date(2026, 9, 18, 23), date(2026, 9, 19, 7),
            listOf(
                Triple(date(2026, 9, 18, 23), date(2026, 9, 19, 1), SleepSessionRecord.STAGE_TYPE_LIGHT),
                Triple(date(2026, 9, 19, 1), date(2026, 9, 19, 3), SleepSessionRecord.STAGE_TYPE_DEEP),
                Triple(date(2026, 9, 19, 3), date(2026, 9, 19, 4), SleepSessionRecord.STAGE_TYPE_AWAKE),
                Triple(date(2026, 9, 19, 4), date(2026, 9, 19, 6), SleepSessionRecord.STAGE_TYPE_REM),
                Triple(date(2026, 9, 19, 6), date(2026, 9, 19, 7), SleepSessionRecord.STAGE_TYPE_OUT_OF_BED),
            ),
        )
        val (health, prefs) = health(fake)
        val sleep = health.nights(prefs.current().clock, heart = false, sleep = true)[friday]?.sleep!!
        assertEquals(2 * 3600.0, sleep.core, 0.1)
        assertEquals(2 * 3600.0, sleep.deep, 0.1)
        assertEquals(2 * 3600.0, sleep.rem, 0.1)
        assertEquals(3600.0, sleep.awake, 0.1)
        assertEquals(6 * 3600.0, sleep.asleep, 0.1)
    }

    @Test fun aSessionWithNoStagesIsUnstagedSleep() {
        val fake = fake()
        val spans = Health.sleepSpans(session(fake, "ring", date(2026, 9, 18, 23), date(2026, 9, 19, 7), emptyList()))
        assertEquals(SleepStage.UNSTAGED, spans.single().stage)
        assertEquals("ring", spans.single().source)
    }

    @Test fun twoDevicesForOneNightTakeTheOneWithMoreSleep() = runBlocking {
        val fake = fake()
        fake.others += session(fake, "phone", date(2026, 9, 18, 23), date(2026, 9, 19, 5), emptyList())
        fake.others += session(fake, "watch", date(2026, 9, 18, 23), date(2026, 9, 19, 7), emptyList())
        val (health, prefs) = health(fake)
        val sleep = health.nights(prefs.current().clock, heart = false, sleep = true)[friday]?.sleep!!
        assertEquals(8 * 3600.0, sleep.asleep, 0.1)
    }

    @Test fun heartRateCountsOnlyWhileAsleep() = runBlocking {
        val fake = fake()
        val bedtime = date(2026, 9, 18, 23)
        val waking = date(2026, 9, 19, 7)
        // Asleep from 11pm to 3am, awake for an hour, asleep again till 7. The 9pm and 3:30am beats are left out.
        fake.others += session(
            fake, "watch", bedtime, waking,
            listOf(
                Triple(bedtime, date(2026, 9, 19, 3), SleepSessionRecord.STAGE_TYPE_LIGHT),
                Triple(date(2026, 9, 19, 3), date(2026, 9, 19, 4), SleepSessionRecord.STAGE_TYPE_AWAKE),
                Triple(date(2026, 9, 19, 4), waking, SleepSessionRecord.STAGE_TYPE_DEEP),
            ),
        )
        fake.others += HeartRateRecord(
            date(2026, 9, 18, 21), ZoneOffset.UTC, waking, ZoneOffset.UTC,
            listOf(
                HeartRateRecord.Sample(date(2026, 9, 18, 21), 90),
                HeartRateRecord.Sample(date(2026, 9, 19, 0), 50),
                HeartRateRecord.Sample(date(2026, 9, 19, 3, 30), 80),
                HeartRateRecord.Sample(date(2026, 9, 19, 5), 54),
            ),
            fake.other("watch"),
        )
        val (health, prefs) = health(fake)
        assertEquals(52.0, health.nights(prefs.current().clock, heart = true, sleep = false)[friday]?.sleepingHR!!, 0.001)
    }

    @Test fun readingsArePagedAndFiledOvernight() = runBlocking {
        val fake = fake()
        // A daytime spot reading is left out, and more readings than a page are all read.
        for ((hour, value) in listOf(23 to 40.0, 24 + 2 to 50.0, 24 + 4 to 60.0, 24 + 15 to 99.0)) {
            fake.others += HeartRateVariabilityRmssdRecord(date(2026, 9, 18).plusSeconds(hour * 3600L), ZoneOffset.UTC, value, fake.other("watch"))
        }
        fake.others += RestingHeartRateRecord(date(2026, 9, 19, 12), ZoneOffset.UTC, 58, fake.other("watch"))
        val (health, prefs) = health(fake)
        val night = health.nights(prefs.current().clock, heart = true, sleep = false)[friday]!!
        assertEquals(50.0, night.hrv!!, 0.001)
        assertEquals(58.0, night.restingHR!!, 0.001)
        assertTrue(fake.reads > 2)
    }

    @Test fun sleepIsDroppedWhenOnlyHeartIsOn() = runBlocking {
        val fake = fake()
        fake.others += session(fake, "watch", date(2026, 9, 18, 23), date(2026, 9, 19, 7), emptyList())
        val (health, prefs) = health(fake)
        assertNull(health.nights(prefs.current().clock, heart = true, sleep = false)[friday]?.sleep)
    }

    @Test fun aWithdrawnPermissionReadsNothingOfItsKind() = runBlocking {
        val fake = FakeHealthConnect(Health.SLEEP)
        fake.others += RestingHeartRateRecord(date(2026, 9, 19, 12), ZoneOffset.UTC, 58, fake.other("watch"))
        val (health, prefs) = health(fake)
        assertTrue(health.nights(prefs.current().clock, heart = true, sleep = true).isEmpty)
    }

    @Test fun historyIsAskedForWithReadingOnly() = runBlocking {
        val (health, _) = health(fake())
        assertTrue(Health.HISTORY in health.withHistory(Health.HEART))
    }
}

/** Health Connect's rationale screen shows the website's policy, read from the page the site serves. */
class PrivacyPolicyTests {
    @Test fun thePolicyPageBreaksIntoHeadingsAndParagraphs() {
        val blocks = PolicyBlock.parse(java.io.File("../../site/public/privacy.html").readText())
        assertEquals(PolicyBlock(true, "Privacy"), blocks.first())
        assertTrue(blocks.any { it.heading && it.html == "Health Connect (Android)" })
        assertTrue(blocks.none { "← GrogLog" in it.html })
    }
}
