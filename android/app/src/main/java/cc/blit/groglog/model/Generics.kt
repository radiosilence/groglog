package cc.blit.groglog.model

import cc.blit.groglog.core.catalogGenerics
import cc.blit.groglog.core.catalogUnitsId
import java.util.UUID

/**
 * The generic drinks the Log grid always offers, from the shared core rather than seeded. Each is the stored generic of
 * its kind when there is one, since the user may have edited or hidden it, else a drink under the generic's fixed id
 * that is stored when first logged or pinned (`Logbook.store`).
 */
object Generics {
    private val records by lazy { catalogGenerics() }

    /** The Units drink as it is first stored. */
    val units by lazy {
        Drink(id = UUID.fromString(catalogUnitsId()), name = "Units", category = DrinkCategory.UNITS, abv = 100.0, vessel = Vessel.SHOT, volumeMl = 10.0, isGeneric = true, sortOrder = 99)
    }

    /**
     * The generic drinks in the core's order, then Units. Hidden ones are left out unless asked for, as Setup lists them
     * to be shown again.
     */
    fun drinks(stored: List<Drink>, includingHidden: Boolean = false): List<Drink> {
        // The lowest id of a kind, the one a sync merge keeps.
        val kept = stored.filter { it.isGeneric }.sortedBy { it.id.toString().uppercase() }
        val generics = records.mapIndexed { order, record ->
            val category = DrinkCategory.of(record.category)
            val first = record.serves.first()
            kept.firstOrNull { it.category == category }
                ?: Drink(id = UUID.fromString(record.id), name = record.name, category = category, abv = category.defaultABV, vessel = Vessel.of(first.vessel), volumeMl = first.ml, price = first.price, isGeneric = true, sortOrder = 100 + order)
        }
        val all = generics + (stored.firstOrNull { it.category == DrinkCategory.UNITS } ?: units)
        return if (includingHidden) all else all.filter { !it.isHidden }
    }

    /** Those not yet stored, to offer alongside the stored drinks. */
    fun unstored(stored: List<Drink>): List<Drink> {
        val ids = stored.mapTo(HashSet()) { it.id }
        return drinks(stored).filter { it.id !in ids }
    }

    /** Each generic drink in its own size, then the other sizes it is commonly drunk in, then Units. */
    fun serves(stored: List<Drink>): List<Serve> = drinks(stored).flatMap { drink ->
        val record = records.firstOrNull { DrinkCategory.of(it.category) == drink.category } ?: return@flatMap listOf(Serve(drink))
        (listOf(ServeSize(drink.vessel, drink.volumeMl)) + record.serves.map { ServeSize(Vessel.of(it.vessel), it.ml) })
            .distinct()
            .map { Serve(drink, it.vessel, it.ml) }
    }
}
