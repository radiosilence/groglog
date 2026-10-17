package cc.blit.groglog.model

import cc.blit.groglog.core.ratesAsOf
import cc.blit.groglog.core.ratesConvert
import cc.blit.groglog.core.ratesCurrencies
import cc.blit.groglog.core.ratesPerPound

/**
 * What a pound buys in each currency, for pricing a drink from one market in another's currency. The table is in the
 * shared core.
 */
object Rates {
    val AS_OF: String by lazy { ratesAsOf() }

    val perPound: Map<String, Double> by lazy { ratesPerPound().associate { it.currency to it.perPound } }

    /** The three original currencies come first; the rest are alphabetical. */
    val currencies: List<String> by lazy { ratesCurrencies() }

    fun convert(amount: Double, from: String, to: String): Double? = ratesConvert(amount, from, to)
}
