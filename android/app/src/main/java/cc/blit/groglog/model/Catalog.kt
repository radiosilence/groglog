package cc.blit.groglog.model

import cc.blit.groglog.data.Seed
import java.text.Normalizer
import java.util.Currency
import java.util.Locale
import kotlin.math.abs

/** One row of the catalogue table in `CatalogEntries.kt`, priced in pounds. */
internal data class CatalogEntry(val name: String, val category: DrinkCategory, val abv: Double, val serves: List<Pair<ServeSize, Double>>)

data class CatalogPrice(val size: ServeSize, val price: Double)

/**
 * Common UK drinks and their usual serves, so logging a specific brand is a search and a tap. ABVs are the UK label
 * figures. A brand brewed at two strengths is two entries (cask London Pride is 4.1%, the bottle 4.7%), because a drink
 * has one strength and rounding the difference away misstates a unit a night. Brands change strength without notice
 * (the 3.5% duty threshold has pulled many lagers down to 3.4%), so anything logged from here becomes an editable drink
 * of the user's own.
 *
 * `prices` holds each usual size with its typical cost: a London bar price for a pint, glass or measure, and a
 * supermarket single price for a can or bottle. Two kinds of figure are estimates rather than lookups. Pubs price
 * draught and by-the-glass by tier rather than by brand, and per-venue prices are rarely published, so a brand with no
 * menu of its own takes its tier's price. Mainstream lager and cider are sold only in multipacks, so those carry the
 * multipack's unit rate, roughly half the price of a single can where one is sold. Craft therefore splits two ways:
 * breweries stocked by supermarkets carry the four-pack rate, and those sold only by bottle shops carry the single-can
 * price, which is why a Camden Hells costs a third of a Verdant. Craft pints are also tiered, banded by strength from
 * the pubs that publish prices: Camden Pale at £6.30, Hepcat and Gamma Ray at £6.90, Camden Hells and Punk IPA at
 * £7.05, Elvis Juice at £7.50. Individual pubs vary by about a pound either way; the figure is a starting price that the
 * user can edit.
 *
 * A drink sold abroad is priced in the market where it is usually bought, in that market's currency, and also in
 * pounds where it is sold in the UK; keyed by currency code.
 */
data class CatalogBrand(
    val name: String,
    val category: DrinkCategory,
    val abv: Double,
    val prices: Map<String, List<CatalogPrice>>,
) {
    val id: String get() = name

    /** Every size any market lists it in, the UK's first. */
    val sizes: List<ServeSize>
        get() = Catalog.marketsInOrder(prices).flatMap { (_, serves) -> serves.map { it.size } }.distinct()
}

/** One brand in one of its usual sizes. */
data class CatalogItem(
    val name: String,
    val category: DrinkCategory,
    val vessel: Vessel,
    val volumeMl: Double,
    val abv: Double,
) {
    /** The price in `currency`: from that market if the brand is sold there, otherwise converted from its home market. */
    fun price(currency: String = Catalog.currency): Double = Catalog.price(name, category, vessel, volumeMl, currency) ?: 0.0

    val id: String get() = "$name|${vessel.raw}|${volumeMl.toInt()}"
    val units: Double get() = Units.of(volumeMl, abv)
}

object Catalog {
    /**
     * Drinks priced in the market where they are usually bought, one block per currency. A drink also in the main table
     * takes these as its home prices alongside its pounds, so it must have the same strength; a different strength
     * requires a different name.
     */
    private val markets: List<Pair<String, List<CatalogEntry>>> = emptyList()

    val brands: List<CatalogBrand> by lazy {
        val merged = LinkedHashMap<String, Triple<CatalogEntry, Double, LinkedHashMap<String, MutableList<CatalogPrice>>>>()
        for ((currency, list) in listOf("GBP" to catalogEntries) + markets) {
            for (entry in list) {
                val id = key(entry.name, entry.category)
                val brand = merged.getOrPut(id) { Triple(entry, entry.abv, LinkedHashMap()) }
                check(brand.second == entry.abv) { "${entry.name} is listed at two strengths" }
                brand.third.getOrPut(currency) { mutableListOf() } += entry.serves.map { CatalogPrice(it.first, it.second) }
            }
        }
        merged.values.map { (entry, abv, prices) -> CatalogBrand(entry.name, entry.category, abv, prices) }
    }

    val items: List<CatalogItem> by lazy {
        brands.flatMap { brand -> brand.sizes.map { CatalogItem(brand.name, brand.category, it.vessel, it.ml, brand.abv) } }
    }

    /**
     * The currency for prices: the one set in Setup. `AppContainer` keeps it in step with `Prefs`, so lookups made
     * outside a screen price the same way as the app.
     */
    @Volatile
    var currency: String = defaultCurrency()

    fun defaultCurrency(): String = runCatching { Currency.getInstance(Locale.getDefault()).currencyCode }.getOrNull() ?: "GBP"

    /** Brands by `key`, for the price and identity lookups that run once per drink per size on every keystroke. */
    private val byKey: Map<String, CatalogBrand> by lazy {
        val map = HashMap<String, CatalogBrand>()
        for (brand in brands) map.putIfAbsent(key(brand.name, brand.category), brand)
        map
    }

    val brandsByCategory: Map<DrinkCategory, List<CatalogBrand>> by lazy { brands.groupBy { it.category } }

    /**
     * Search keys, folded once: search runs on every keystroke over a few thousand serves, and folding each one per
     * keystroke dominated the cost.
     */
    private val searchKeys: List<String> by lazy { items.map { "${it.name} ${it.category.label}".searchFolded } }

    /** A drink's identity as the catalogue sees it: same name, same kind. */
    fun key(name: String, category: DrinkCategory) = "$name|${category.raw}"

    /** Whether a drink still matches the catalogue exactly. Changing its name, kind or strength makes it the user's own. */
    fun holds(name: String, category: DrinkCategory, abv: Double) = byKey[key(name, category)]?.abv == abv

    /** The sizes a drink of this name and kind is listed in, or none for a drink the catalogue does not know. */
    fun sizes(name: String, category: DrinkCategory): List<ServeSize> = byKey[key(name, category)]?.sizes ?: emptyList()

    /**
     * The normal price of a drink of this name in this size: a brand's own price, else a generic's starting price. Null
     * when unknown, so callers can distinguish unpriced from free.
     */
    fun price(name: String, category: DrinkCategory, vessel: Vessel, ml: Double, currency: String = this.currency): Double? {
        byKey[key(name, category)]?.let { brand ->
            val found = price(brand, vessel, ml, currency)
            return if (found > 0) found else null
        }
        return Seed.price(name, vessel, ml)?.let { Rates.convert(it, "GBP", currency) }
    }

    /**
     * A size the brand is not listed in scales from the nearest serve of the same vessel first: a 440 ml bottle is the
     * 330's price plus a third, not a pint's less a fifth. Draught and packaged prices are not proportional to each
     * other.
     *
     * A drink sold in `currency`'s market is priced from that market alone. Otherwise it is converted from wherever it
     * is priced, the UK first, at the bundled rates.
     */
    fun price(brand: CatalogBrand, vessel: Vessel, ml: Double, currency: String = this.currency): Double {
        brand.prices[currency]?.let { return price(it, vessel, ml) }
        for ((source, serves) in marketsInOrder(brand.prices)) {
            Rates.convert(price(serves, vessel, ml), source, currency)?.let { return it }
        }
        return 0.0
    }

    private fun price(serves: List<CatalogPrice>, vessel: Vessel, ml: Double): Double {
        serves.firstOrNull { it.size.vessel == vessel && it.size.ml == ml }?.let { return it.price }
        val nearest = serves.filter { it.size.vessel == vessel }.minByOrNull { abs(it.size.ml - ml) } ?: serves.firstOrNull() ?: return 0.0
        return nearest.price * ml / nearest.size.ml
    }

    fun search(query: String): List<CatalogItem> {
        val folded = query.trim().searchFolded
        if (folded.isEmpty()) return emptyList()
        return items.filterIndexed { index, _ -> searchKeys[index].contains(folded) }
    }

    /** Pounds first, then the other markets by currency code. */
    internal fun <T> marketsInOrder(prices: Map<String, T>): List<Pair<String, T>> =
        prices.toList().sortedWith(compareBy<Pair<String, T>> { it.first != "GBP" }.thenBy { it.first })
}

/** Case and accents folded, so "stella" finds Stella and "kolsch" finds Kölsch. */
val String.searchFolded: String
    get() = Normalizer.normalize(this, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase(Locale.ROOT)
