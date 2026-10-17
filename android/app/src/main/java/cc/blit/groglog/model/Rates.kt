package cc.blit.groglog.model

import cc.blit.groglog.core.ratesCurrencies

/** The currencies a price can be set in. The rates between them are in the shared core. */
object Rates {
    /** The three original currencies come first; the rest are alphabetical. */
    val currencies: List<String> by lazy { ratesCurrencies() }
}
