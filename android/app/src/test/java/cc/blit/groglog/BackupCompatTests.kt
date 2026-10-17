package cc.blit.groglog

import cc.blit.groglog.export.Exporter
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Iso8601
import cc.blit.groglog.model.Taper
import cc.blit.groglog.model.Vessel
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * A backup is the way a log moves between an iPhone and an Android phone, so each must read the other's. The fixture
 * was written by the iOS app's own encoder, before the document moved into the shared core. The core's tests read the
 * same file, and hold its number and layout rules.
 */
@RunWith(RobolectricTestRunner::class)
class BackupCompatTests {
    private val ios = javaClass.getResourceAsStream("/ios-backup.json")!!.use { it.readBytes() }

    @Test fun anIOSBackupIsWrittenBackByteForByte() {
        assertArrayEquals(ios, Exporter.json(Exporter.decode(ios)))
    }

    @Test fun anIOSBackupImports() = runBlocking {
        val prefs = prefs()
        val database = database()
        assertEquals(3, Exporter.restore(ios, database, prefs))

        val settings = prefs.current()
        assertEquals(5, settings.rolloverHour)
        assertEquals("GBP", settings.currency)
        assertEquals(Taper.LINEAR, settings.goal.taper)
        assertEquals(52.5, settings.goal.baselineWeekly, 0.0)
        assertEquals(1.5, settings.goal.reductionUnits, 0.0)
        assertEquals(Iso8601.parse("2026-09-01T04:00:00Z"), settings.goal.start)

        val rows = database.rows()
        val rose = rows.drink(UUID.fromString("0B9C1E4A-6D2F-4C8E-9A51-3F7B2D8E1C40"))!!
        assertEquals("Rosé de Provence / Kölsch \"test\"\\ \u0001", rose.name)
        assertTrue(rose.isHidden && rose.category == DrinkCategory.ROSE && rose.vessel == Vessel.WINE_GLASS)
        assertEquals(Vessel.CAN, rows.favourites().single().vessel)

        val pours = rows.entries()
        assertEquals(3, pours.size)
        val glass = pours.single { it.id == UUID.fromString("C3E85A12-7B9F-4D21-A06E-2F4B8D17C590") }
        assertEquals("logged at its own strength", 13.6, glass.pour.abvOverride!!, 0.0)
        assertEquals(Iso8601.parse("2026-10-11T21:40:00Z"), glass.timestamp)
        val units = pours.single { it.category == DrinkCategory.UNITS }
        assertEquals(1e21, units.kcal, 0.0)

        val sunday = rows.day(DayKey.of(2026, 10, 11).number)!!
        assertEquals(20.0, sunday.costOverride!!, 0.0)
        assertEquals(2, sunday.count)
        assertTrue(rows.day(DayKey.of(2026, 10, 10).number)!!.isAlcoholFree)
    }

    /** What Android writes, iOS reads: the same file comes back out after a pass through an Android log. */
    @Test fun anAndroidExportCarriesTheIOSLogAcross() = runBlocking {
        val prefs = prefs()
        val first = database()
        Exporter.restore(ios, first, prefs)
        val exported = Exporter.backup(first, prefs.current())
        val second = database()
        Exporter.restore(Exporter.json(exported), second, prefs)
        assertEquals(first.rows().entries().map { it.pour }.toSet(), second.rows().entries().map { it.pour }.toSet())
        assertEquals(first.rows().days().toSet(), second.rows().days().toSet())
        assertEquals(first.rows().drinks().toSet(), second.rows().drinks().toSet())
    }
}
