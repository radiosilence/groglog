package cc.blit.groglog

import androidx.compose.foundation.text.input.setTextAndPlaceCursorAtEnd
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.export.Exporter
import cc.blit.groglog.export.ImportException
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.Taper
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.ui.setup.DrinkEditorViewModel
import cc.blit.groglog.ui.setup.GoalViewModel
import cc.blit.groglog.ui.setup.Notice
import cc.blit.groglog.ui.setup.SetupViewModel
import cc.blit.groglog.ui.setup.moneyDigits
import cc.blit.groglog.ui.setup.moneyValue
import cc.blit.groglog.ui.setup.parseDecimal
import java.io.ByteArrayInputStream
import java.io.File
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class SetupTests {
    private val ios = javaClass.getResourceAsStream("/ios-backup.json")!!.use { it.readBytes() }

    @Before fun setUp() = Dispatchers.setMain(Dispatchers.Unconfined)

    @After fun tearDown() = Dispatchers.resetMain()

    private fun setup(database: AppDatabase = database(), prefs: Prefs = prefs()) =
        SetupViewModel(database, prefs, CoroutineScope(SupervisorJob() + Dispatchers.Default), File(System.getProperty("java.io.tmpdir"), "groglog-exports"))

    private suspend fun local(prefs: Prefs, database: AppDatabase) = Logbook(database, prefs.current().clock)

    // Import and export

    @Test fun anIOSBackupImportsAndSaysHowMuch() = runBlocking {
        val database = database()
        val notice = setup(database).import { ByteArrayInputStream(ios) }
        assertEquals(Notice.Dialog("Backup imported", "Imported 3 drinks."), notice)
        assertEquals(3, database.rows().pours().size)
    }

    @Test fun importingTheSameBackupTwiceAddsNothing() = runBlocking {
        val model = setup()
        model.import { ByteArrayInputStream(ios) }
        assertEquals(Notice.Dialog("Backup imported", "Imported 0 drinks."), model.import { ByteArrayInputStream(ios) })
    }

    @Test fun aFileThatIsNotABackupIsRefusedInWords() = runBlocking {
        val database = database()
        val notice = setup(database).import { ByteArrayInputStream("<html>not json</html>".toByteArray()) }
        assertEquals(Notice.Dialog("Import failed", "The file is not a GrogLog backup, or it is damaged."), notice)
        assertTrue(database.rows().pours().isEmpty())
    }

    @Test fun aBackupWithAnImpossibleDayEndIsRefused() = runBlocking {
        val prefs = prefs()
        val notice = setup(prefs = prefs).import { ByteArrayInputStream("""{"dayStartsAtHour": 30, "days": []}""".toByteArray()) }
        assertEquals(Notice.Dialog("Import failed", ImportException.dayEndsAtImpossibleHour(30).message!!), notice)
        assertEquals(5, prefs.current().rolloverHour)
    }

    @Test fun anOversizedFileIsRefusedBeforeItIsAllRead() {
        val stream = object : java.io.InputStream() {
            var served = 0
            override fun read() = if (served++ < 1_000_000) 0 else -1
        }
        try {
            SetupViewModel.readBackup(stream, limit = 100)
            fail("Read an oversized file")
        } catch (error: ImportException) {
            assertEquals(ImportException.tooLarge().message, error.message)
        }
        assertTrue(stream.served < 1_000_000)
        assertEquals(5, SetupViewModel.readBackup(ByteArrayInputStream(ByteArray(5)), limit = 5).size)
    }

    @Test fun anExportedBackupRestoresOntoAnotherPhone() = runBlocking {
        val prefs = prefs()
        val database = database()
        val logbook = local(prefs, database)
        val drink = logbook.drink("Hepcat", DrinkCategory.BEER, 4.6, Vessel.PINT, 568.0, 6.5)!!
        logbook.log(Serve(drink), listOf(Instant.now().minusSeconds(3_600), Instant.now()))

        val bytes = setup(database, prefs).export(Exporter.Kind.JSON)
        val elsewhere = database()
        assertEquals(Notice.Dialog("Backup imported", "Imported 2 drinks."), setup(elsewhere).import { ByteArrayInputStream(bytes) })
        assertEquals(2, elsewhere.rows().pours().size)
        assertEquals("Hepcat", elsewhere.rows().drink(drink.id)!!.name)
    }

    @Test fun theMarkdownExportIsAReadableLog() = runBlocking {
        val prefs = prefs()
        val database = database()
        val logbook = local(prefs, database)
        val drink = logbook.drink("Hepcat", DrinkCategory.BEER, 4.6, Vessel.PINT, 568.0, 6.5)!!
        logbook.log(Serve(drink), listOf(Instant.now()))

        val model = setup(database, prefs)
        val file = model.exportFile(Exporter.Kind.MARKDOWN)
        val text = file.readText()
        assertTrue(text.startsWith("# Drinking log"))
        assertTrue(text.contains("Hepcat"))
        assertTrue(file.name.endsWith(".md"))
        assertTrue(model.fileName(Exporter.Kind.JSON).matches(Regex("""groglog-\d{4}-\d{2}-\d{2}\.json""")))
    }

    // Settings

    @Test fun movingTheDayEndMovesEntriesToTheirNewDay() = runBlocking {
        val prefs = prefs()
        val database = database()
        val zone = ZoneId.systemDefault()
        val logbook = local(prefs, database)
        val drink = logbook.drink("Beer", DrinkCategory.BEER, 4.0, Vessel.PINT, 568.0)!!
        // 3am, before a 5am day end: last night. With the day ending at 2am, it is the new day.
        val time = LocalDateTime.now(zone).minusDays(2).withHour(3).withMinute(0).atZone(zone).toInstant()
        logbook.log(Serve(drink), listOf(time))
        val before = database.rows().pours().single().day

        setup(database, prefs).setRolloverHour(2).join()

        assertEquals(2, prefs.current().rolloverHour)
        assertEquals(before + 1, database.rows().pours().single().day)
        assertEquals(DayClock(2).day(time).number, database.rows().days().single().number)
    }

    @Test fun resettingPricesSaysHowManyChanged() = runBlocking {
        val prefs = prefs()
        val database = database()
        local(prefs, database).drink("Beer", DrinkCategory.BEER, 4.0, Vessel.PINT, 568.0, price = 1.0)
        val model = setup(database, prefs)
        model.resetPrices().join()
        assertEquals(Notice.Dialog("Prices reset", "1 price changed."), model.notice.value)
        model.resetPrices().join()
        assertEquals(Notice.Dialog("Prices reset", "Everything already matched the catalogue."), model.notice.value)
    }

    // The drink editor

    private suspend fun editor(database: AppDatabase, prefs: Prefs, id: java.util.UUID? = null, name: String = "") =
        DrinkEditorViewModel(database, prefs, id, name).also { it.draft.first { draft -> draft != null } }

    @Test fun impossibleStrengthsAreRefused() = runBlocking {
        val model = editor(database(), prefs())
        model.name.setTextAndPlaceCursorAtEnd("Hepcat")
        for (figure in listOf("0", "0.0", "100.1", "250", "", ".")) {
            model.strength.setTextAndPlaceCursorAtEnd(figure)
            assertFalse("Accepted $figure", model.canSave)
            assertFalse("Saved $figure", model.save())
        }
        for (figure in listOf("0.5", "4.6", "100")) {
            model.strength.setTextAndPlaceCursorAtEnd(figure)
            assertTrue("Refused $figure", model.canSave)
        }
    }

    @Test fun aNewDrinkStartsFromTheNameSearchedFor() = runBlocking {
        val model = editor(database(), prefs(), name = "Hepcat")
        assertEquals("Hepcat", model.name.text.toString())
        assertTrue(model.canSave)
    }

    @Test fun aDrinkNeedsAName() = runBlocking {
        val model = editor(database(), prefs())
        model.name.setTextAndPlaceCursorAtEnd("   ")
        assertFalse(model.canSave)
        model.name.setTextAndPlaceCursorAtEnd("  Hepcat ")
        assertEquals("Hepcat", model.edited()!!.name)
    }

    @Test fun aNewDrinkIsAddedToTheGridAtItsPrice() = runBlocking {
        val database = database()
        val model = editor(database, prefs())
        model.name.setTextAndPlaceCursorAtEnd("Hepcat")
        model.strength.setTextAndPlaceCursorAtEnd("4.6")
        model.price.setTextAndPlaceCursorAtEnd("690")
        assertTrue(model.save())
        val drink = database.rows().drinks().single()
        assertEquals(4.6, drink.abv, 0.0)
        assertEquals(6.9, drink.price, 0.0001)
        assertEquals(drink.id, database.rows().favourites().single().drinkId)
    }

    @Test fun changingTheTypeOfANewDrinkResetsItsSizeAndStrength() = runBlocking {
        val model = editor(database(), prefs())
        model.setCategory(DrinkCategory.RED_WINE)
        assertEquals(Vessel.WINE_GLASS, model.draft.value!!.vessel)
        assertEquals(125.0, model.draft.value!!.volumeMl, 0.0)
        assertEquals(12.0, parseDecimal(model.strength.text)!!, 0.0)
    }

    @Test fun aCorrectedStrengthCarriesToEverythingLoggedAsTheDrink() = runBlocking {
        val prefs = prefs()
        val database = database()
        val logbook = local(prefs, database)
        val drink = logbook.drink("Hepcat", DrinkCategory.BEER, 46.0, Vessel.PINT, 568.0)!!
        logbook.log(Serve(drink), listOf(Instant.now()))
        assertEquals(26.1, database.rows().days().single().units, 0.05)

        val model = editor(database, prefs, drink.id)
        model.setCategory(DrinkCategory.STOUT)
        assertEquals("An existing drink keeps its strength when its type changes", 46.0, parseDecimal(model.strength.text)!!, 0.0)
        model.strength.setTextAndPlaceCursorAtEnd("4.6")
        assertTrue(model.save())

        assertEquals(2.6, database.rows().days().single().units, 0.05)
        assertEquals(DrinkCategory.STOUT, database.rows().drink(drink.id)!!.category)
    }

    @Test fun savingAsNewLeavesTheOldDrinkAndItsEntries() = runBlocking {
        val prefs = prefs()
        val database = database()
        val logbook = local(prefs, database)
        val drink = logbook.drink("Hepcat", DrinkCategory.BEER, 4.6, Vessel.PINT, 568.0)!!
        logbook.log(Serve(drink), listOf(Instant.now()))

        val model = editor(database, prefs, drink.id)
        assertEquals(1, model.timesLogged.first { it == 1 })
        model.name.setTextAndPlaceCursorAtEnd("Hepcat (can)")
        model.strength.setTextAndPlaceCursorAtEnd("5")
        assertTrue(model.saveAsNew())

        assertEquals(4.6, database.rows().drink(drink.id)!!.abv, 0.0)
        assertEquals(listOf("Hepcat", "Hepcat (can)"), database.rows().drinks().map { it.name }.sorted())
    }

    @Test fun moneyFillsFromThePenceUp() {
        assertEquals(1.5, moneyValue("150", "GBP"), 0.0)
        assertEquals(150.0, moneyValue("150", "JPY"), 0.0)
        assertEquals("690", moneyDigits(6.9, "GBP"))
        assertEquals(0.0, moneyValue("", "EUR"), 0.0)
    }

    // The goal editor

    private suspend fun goalEditor(prefs: Prefs) = GoalViewModel(database(), prefs).also { it.draft.first { goal -> goal != null } }

    @Test fun aGoalOpensOnAPaceItsStartingFigureAllows() = runBlocking {
        val prefs = prefs()
        // A day apart is not offered above 15 units a day.
        prefs.setGoal(Goal(isEnabled = true, taper = Taper.PROPORTIONAL, baselineWeekly = 140.0, periodDays = 1))
        assertEquals(3, goalEditor(prefs).goal!!.periodDays)
    }

    @Test fun aGoalThatWasOffOpensSwitchedOnAndStartingNow() = runBlocking {
        val prefs = prefs()
        prefs.setGoal(Goal(isEnabled = false, start = Instant.parse("2020-01-01T12:00:00Z")))
        val model = goalEditor(prefs)
        val goal = model.goal!!
        assertTrue(goal.isEnabled)
        assertTrue(goal.start.isAfter(Instant.now().minusSeconds(60)))
    }

    @Test fun raisingTheStartingFigureSlowsAPaceNoLongerOffered() = runBlocking {
        val prefs = prefs()
        prefs.setGoal(Goal(isEnabled = true, taper = Taper.PROPORTIONAL, baselineWeekly = 70.0, periodDays = 1))
        val model = goalEditor(prefs)
        assertEquals(1, model.goal!!.periodDays)

        // While typing nothing moves; it settles when editing ends.
        model.from.setTextAndPlaceCursorAtEnd("30")
        assertEquals(1, model.goal!!.periodDays)
        model.settle()
        assertEquals(4, model.goal!!.periodDays)
        assertEquals(210.0, model.goal!!.baselineWeekly, 0.0)
    }

    @Test fun aLinearCutTooLargeForTheStartingFigureIsNotKept() = runBlocking {
        val prefs = prefs()
        prefs.setGoal(Goal(isEnabled = true, taper = Taper.LINEAR, baselineWeekly = 70.0, reductionUnits = 1.0, periodDays = 1))
        val model = goalEditor(prefs)
        assertEquals(1.0, model.goal!!.reductionUnits, 0.0)
        model.from.setTextAndPlaceCursorAtEnd("6")
        model.settle()
        assertEquals(1, model.goal!!.periodDays)
        assertEquals(0.5, model.goal!!.reductionUnits, 0.0)
    }

    @Test fun theRecentAverageIsRoundedToAWholeUnitADay() = runBlocking {
        val model = goalEditor(prefs())
        model.useRecent(30.486 * 7)
        assertEquals(210.0, model.goal!!.baselineWeekly, 0.0)
        assertEquals(30.0, parseDecimal(model.from.text)!!, 0.0)
    }

    @Test fun aGoalNeedsAStartingFigure() = runBlocking {
        val prefs = prefs()
        val model = goalEditor(prefs)
        model.from.setTextAndPlaceCursorAtEnd("")
        assertFalse(model.canSave)
        model.from.setTextAndPlaceCursorAtEnd("12")
        model.target.setTextAndPlaceCursorAtEnd("2")
        assertTrue(model.canSave)
        model.save()
        assertEquals(84.0, prefs.current().goal.baselineWeekly, 0.0)
        assertEquals(14.0, prefs.current().goal.targetWeekly, 0.0)
    }
}
