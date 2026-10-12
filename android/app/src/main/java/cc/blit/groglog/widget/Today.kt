package cc.blit.groglog.widget

import androidx.compose.ui.graphics.Color
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Serves
import cc.blit.groglog.model.CurvePoint
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.model.leftText
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.HeatBand
import java.time.Instant
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest

/** What both widgets show: today against its budget, and the tiles to log from. */
data class Today(
    val units: Double = 0.0,
    val budget: Double? = null,
    val isDry: Boolean = false,
    /** Units through the day, stepping at each drink: the same running total the Day screen draws. */
    val curve: List<CurvePoint> = emptyList(),
    /** Tiles to log from, most recently drunk first. */
    val tiles: List<Serve> = emptyList(),
) {
    /** The line under the total: what remains of the budget, or that the day was dry. */
    val detail: String
        get() = if (isDry) "Alcohol-free" else budget?.let { units.leftText(it) } ?: "today"

    /** Teal inside the budget, amber just over, red well past it. */
    val heat: Color get() = GrogColors.heat(units, budget)

    /** The share of the budget still left, 0 once it is spent, as the Day screen's budget bar drains. */
    val left: Float?
        get() = budget?.takeIf { it > 0 }?.let { ((it - units) / it).coerceIn(0.0, 1.0).toFloat() }

    val isOver: Boolean get() = budget != null && units > budget

    /**
     * The budget draining through the day or, with no goal, the units climbing. Once spent, the line stays at zero
     * rather than going negative, since the detail line already reports how far over.
     */
    val burndown: List<CurvePoint>
        get() = budget?.let { budget -> curve.map { CurvePoint(it.x, maxOf(0.0, budget - it.units)) } } ?: curve

    /** For TalkBack, which cannot tell the heat colours apart. */
    val spoken: String
        get() = when {
            isDry -> "Today is alcohol-free"
            budget == null -> "${units.unitsText} units today"
            else -> "${units.unitsText} units today, ${units.leftText(budget)}, ${HeatBand.of(units, budget).spoken}"
        }

    companion object {
        /** Four at most: a tile that has to be hunted for on a home screen is no faster than opening the app. */
        const val TILES = 4

        /** Today, re-read after every commit that could change it and whenever the settings change. */
        @OptIn(ExperimentalCoroutinesApi::class)
        fun observe(database: AppDatabase, prefs: Prefs): Flow<Today> =
            prefs.settings.flatMapLatest { settings ->
                val clock = settings.clock
                val day = clock.today
                val queries = database.queries()
                combine(queries.days(), queries.entries(day..day), queries.favourites()) { days, entries, _ ->
                    val ledger = Ledger(days, clock)
                    Today(
                        units = ledger.totals(day).units,
                        budget = ledger.dailyBudget(day, settings.goal),
                        isDry = ledger.status(day) == DayStatus.ALCOHOL_FREE,
                        // Only as far as now: drawing the rest of the day flat would imply nothing more was drunk.
                        curve = ledger.cumulative(entries, day, through = clock.hours(Instant.now(), day)),
                        tiles = Serves.grid(database).take(TILES),
                    )
                }
            }.distinctUntilChanged()

        /** The widget picker's preview, with the iOS previews' figures. */
        val sample = Today(
            units = 3.5,
            budget = 4.5,
            curve = listOf(CurvePoint(0.0, 0.0), CurvePoint(13.0, 1.2), CurvePoint(15.0, 3.5), CurvePoint(16.0, 3.5)),
            tiles = listOf(
                Drink(name = "Staropramen", category = DrinkCategory.BEER, abv = 5.0, vessel = Vessel.PINT, volumeMl = 568.0),
                Drink(name = "Fuller's London Pride (bottle)", category = DrinkCategory.BEER, abv = 4.7, vessel = Vessel.BOTTLE, volumeMl = 500.0),
                Drink(name = "Red wine", category = DrinkCategory.RED_WINE, abv = 12.0, vessel = Vessel.WINE_GLASS, volumeMl = 175.0),
                Drink(name = "Whisky", category = DrinkCategory.SPIRIT, abv = 40.0, vessel = Vessel.TUMBLER, volumeMl = 50.0),
            ).map(::Serve),
        )
    }
}
