package cc.blit.groglog.model

import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.Relation
import java.time.Instant
import java.util.Locale
import java.util.UUID

/**
 * A drink's identity: name, type and strength. Sizes belong to Log-grid favourites and log entries, so one Staropramen
 * covers the 440 can and the 660 bottle. The default size and price are those it was first added with.
 */
@Entity(tableName = "drink")
data class Drink(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val name: String,
    val category: DrinkCategory,
    val abv: Double,
    val vessel: Vessel,
    val volumeMl: Double,
    val price: Double = 0.0,
    val isGeneric: Boolean = false,
    val isHidden: Boolean = false,
    val sortOrder: Int = 0,
) {
    /**
     * The price in a given size. The stored price belongs to the size the drink was added in; other sizes are looked
     * up in the catalogue rather than scaled, since Asahi is £7.40 a pint but £1.63 for a 330 ml bottle, not the £4.30
     * scaling would give. Only drinks unknown to the catalogue are scaled by volume.
     */
    fun price(vessel: Vessel, ml: Double): Double {
        if (vessel == this.vessel && ml == volumeMl) return price
        Catalog.price(name, category, vessel, ml)?.let { return it }
        return price * ml / volumeMl
    }

    /**
     * The sizes to offer, led by `size` when it is not among them: the catalogue's sizes for this drink, then its
     * type's usual sizes. A type's sizes are a default, so Buckfast is offered in the 750 ml bottle it is sold in as
     * well as the fortified-wine pours.
     */
    fun sizes(including: ServeSize): List<ServeSize> {
        val usual = (Catalog.sizes(name, category) + category.serves).distinct()
        return if (including in usual) usual else listOf(including) + usual
    }
}

/** A drink in a particular size, pinned to the Log grid with its usual price. */
@Entity(
    tableName = "favourite",
    foreignKeys = [ForeignKey(entity = Drink::class, parentColumns = ["id"], childColumns = ["drinkId"], onDelete = ForeignKey.CASCADE)],
    indices = [Index("drinkId")],
)
data class Favourite(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val drinkId: UUID,
    val vessel: Vessel,
    val volumeMl: Double,
    val price: Double,
    val sortOrder: Int = 0,
    /** When it was last logged, for ordering by recent use without scanning history. */
    val lastUsed: Instant? = null,
)

/**
 * A logged drink: which drink, plus when, what size and what it cost. Name, strength and type come from the drink, so
 * correcting a drink corrects everything logged as it, except where this one was logged at its own strength.
 */
@Entity(
    tableName = "pour",
    foreignKeys = [ForeignKey(entity = Drink::class, parentColumns = ["id"], childColumns = ["drinkId"], onDelete = ForeignKey.RESTRICT)],
    // Entries are always read by day and in time order, so the index holds both and the rows come back sorted.
    indices = [Index("drinkId"), Index(value = ["day", "timestamp"], name = "pour_on_day_timestamp")],
)
data class Pour(
    @PrimaryKey val id: UUID = UUID.randomUUID(),
    val drinkId: UUID,
    val timestamp: Instant,
    /** The drinking day (`DayKey.number`) it counted towards when logged, so entries are fetched by day and stay put across timezones. */
    val day: Int,
    val vessel: Vessel,
    val volumeMl: Double,
    /** What it cost at the time. Prices change, so this is copied rather than read from the drink. */
    val price: Double,
    /** Calories supplied by another app's import; otherwise they are derived from the drink. */
    val kcalOverride: Double? = null,
    /**
     * The strength this one was logged at, when it differs from the drink's: a guest ale logged as Beer at the pump
     * clip's 5.2%, without making a drink of it.
     */
    val abvOverride: Double? = null,
) {
    val dayKey: DayKey get() = DayKey(day)
}

/**
 * One drinking day's totals, kept in step with its entries by `Logbook`, plus whether it was marked alcohol-free.
 * Reports, the calendar and budgets read only these (a few hundred rows a year), never the entries. A day with neither
 * drinks nor a dry mark has no row.
 */
@Entity(tableName = "day")
data class Day(
    @PrimaryKey val number: Int,
    val isAlcoholFree: Boolean = false,
    val units: Double = 0.0,
    val kcal: Double = 0.0,
    val cost: Double = 0.0,
    val count: Int = 0,
    /** A manually entered spend for the day, used instead of the sum of prices. When null, spend is `cost`. */
    val costOverride: Double? = null,
) {
    val key: DayKey get() = DayKey(number)
    val spend: Double get() = costOverride ?: cost

    fun with(totals: DayTotals) = copy(units = totals.units, kcal = totals.kcal, cost = totals.cost, count = totals.count)
}

/** A log entry joined with its drink, as screens display it. */
data class Entry(
    @Embedded val pour: Pour,
    @Relation(parentColumn = "drinkId", entityColumn = "id") val drink: Drink,
) {
    val id: UUID get() = pour.id
    val name: String get() = drink.name
    val category: DrinkCategory get() = drink.category
    val abv: Double get() = pour.abvOverride ?: drink.abv
    val vessel: Vessel get() = pour.vessel
    val volumeMl: Double get() = pour.volumeMl
    val price: Double get() = pour.price
    val timestamp: Instant get() = pour.timestamp
    val day: Int get() = pour.day
    val dayKey: DayKey get() = pour.dayKey
    val units: Double get() = Units.of(pour.volumeMl, abv)
    val kcal: Double get() = pour.kcalOverride ?: Units.kcal(pour.volumeMl, abv, drink.category)
    val serveKey: String get() = Serve.key(drink.id, pour.vessel, pour.volumeMl)

    /** Standard drinks of 17.7 ml of alcohol, as other apps count them, rather than UK units of 10 ml. */
    val standardDrinks: Double get() = units * Units.UNIT_ML / Units.STANDARD_DRINK_ML
}

/** A favourite with its drink. */
data class FavouriteItem(
    @Embedded val favourite: Favourite,
    @Relation(parentColumn = "drinkId", entityColumn = "id") val drink: Drink,
) {
    val serve: Serve get() = Serve(drink, favourite.vessel, favourite.volumeMl, favourite.price, favourite)
}

/** A drink in a size with its assumed price: the model behind a Log tile and the source of a new log entry. */
data class Serve(
    val drink: Drink,
    val vessel: Vessel,
    val volumeMl: Double,
    val price: Double = drink.price(vessel, volumeMl),
    val favourite: Favourite? = null,
) {
    /** The drink's default size. */
    constructor(drink: Drink) : this(drink, drink.vessel, drink.volumeMl, drink.price)

    val id: String get() = key(drink.id, vessel, volumeMl)
    val units: Double get() = Units.of(volumeMl, drink.abv)

    companion object {
        fun key(drink: UUID, vessel: Vessel, volumeMl: Double) =
            "${drink.toString().uppercase(Locale.ROOT)}|${vessel.raw}|${volumeMl.toInt()}"
    }
}
