package cc.blit.groglog.model

import cc.blit.groglog.core.BrandRecord
import cc.blit.groglog.core.catalogBrandPrice
import cc.blit.groglog.core.catalogBrands
import cc.blit.groglog.core.catalogHolds
import cc.blit.groglog.core.catalogItems
import cc.blit.groglog.core.catalogPrice
import cc.blit.groglog.core.catalogSearch
import cc.blit.groglog.core.catalogSizes
import java.text.Normalizer
import java.util.Currency
import java.util.Locale

data class CatalogPrice(val size: ServeSize, val price: Double)

/**
 * A catalogue brand: common UK drinks and their usual serves, so logging a specific brand is a search and a tap. The
 * table, the prices and the lookups live in the shared core, which both apps read.
 *
 * `prices` holds each usual size with its typical cost, per market, keyed by currency code.
 */
data class CatalogBrand(
    val name: String,
    val category: DrinkCategory,
    val abv: Double,
    val prices: Map<String, List<CatalogPrice>>,
    /** Every size any market lists it in, the UK's first. */
    val sizes: List<ServeSize>,
) {
    val id: String get() = name
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

private fun serveSize(vessel: String, ml: Double): ServeSize? = Vessel.fromRaw(vessel)?.let { ServeSize(it, ml) }

private fun brand(record: BrandRecord): CatalogBrand? {
    val category = DrinkCategory.fromRaw(record.category) ?: return null
    val prices = LinkedHashMap<String, List<CatalogPrice>>()
    for (market in record.markets) {
        prices[market.currency] = market.serves.mapNotNull { serve -> serveSize(serve.vessel, serve.ml)?.let { CatalogPrice(it, serve.price) } }
    }
    return CatalogBrand(record.name, category, record.abv, prices, record.sizes.mapNotNull { serveSize(it.vessel, it.ml) })
}

object Catalog {
    val brands: List<CatalogBrand> by lazy { catalogBrands().mapNotNull(::brand) }

    /** Every brand in every size; `search` answers with positions in this list. */
    val items: List<CatalogItem> by lazy {
        catalogItems().mapNotNull { record ->
            val category = DrinkCategory.fromRaw(record.category) ?: return@mapNotNull null
            val vessel = Vessel.fromRaw(record.vessel) ?: return@mapNotNull null
            CatalogItem(record.name, category, vessel, record.ml, record.abv)
        }
    }

    /**
     * The currency for prices: the one set in Setup. `AppContainer` keeps it in step with `Prefs`, so lookups made
     * outside a screen price the same way as the app.
     */
    @Volatile
    var currency: String = defaultCurrency()

    fun defaultCurrency(): String = runCatching { Currency.getInstance(Locale.getDefault()).currencyCode }.getOrNull() ?: "GBP"

    val brandsByCategory: Map<DrinkCategory, List<CatalogBrand>> by lazy { brands.groupBy { it.category } }

    /** A drink's identity as the catalogue sees it: same name, same kind. */
    fun key(name: String, category: DrinkCategory) = "$name|${category.raw}"

    /** Whether a drink still matches the catalogue exactly. Changing its name, kind or strength makes it the user's own. */
    fun holds(name: String, category: DrinkCategory, abv: Double) = catalogHolds(name, category.raw, abv)

    /** The sizes a drink of this name and kind is listed in, or none for a drink the catalogue does not know. */
    fun sizes(name: String, category: DrinkCategory): List<ServeSize> =
        catalogSizes(name, category.raw).mapNotNull { serveSize(it.vessel, it.ml) }

    /**
     * The normal price of a drink of this name in this size: a brand's own price, else a generic's starting price. Null
     * when unknown, so callers can distinguish unpriced from free.
     */
    fun price(name: String, category: DrinkCategory, vessel: Vessel, ml: Double, currency: String = this.currency): Double? =
        catalogPrice(name, category.raw, vessel.raw, ml, currency)

    /**
     * A size the brand is not listed in scales from the nearest serve of the same vessel first, and a drink sold in
     * another currency's market is converted at the bundled rates.
     */
    fun price(brand: CatalogBrand, vessel: Vessel, ml: Double, currency: String = this.currency): Double =
        catalogBrandPrice(brand.name, brand.category.raw, vessel.raw, ml, currency)

    fun search(query: String): List<CatalogItem> = catalogSearch(query).map { items[it.toInt()] }
}

/** Case and accents folded, so "stella" finds Stella and "kolsch" finds Kölsch. */
val String.searchFolded: String
    get() = Normalizer.normalize(this, Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase(Locale.ROOT)
