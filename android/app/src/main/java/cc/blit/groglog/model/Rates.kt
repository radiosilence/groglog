package cc.blit.groglog.model

/**
 * What a pound buys in each currency, for pricing a drink from one market in another's currency.
 *
 * A dated snapshot of the ECB's reference rates. A catalogue price is only a starting point that the user owns once
 * copied in, so it does not justify requiring a network connection. A drink priced in the user's own currency is never
 * converted.
 */
object Rates {
    const val AS_OF = "2026-09-25"

    /** The three original currencies come first; the rest are alphabetical. */
    val perPound: Map<String, Double> = linkedMapOf(
        "GBP" to 1.0,
        "EUR" to 1.16218,
        "USD" to 1.32524,
        "AUD" to 1.88506,
        "BRL" to 6.86745,
        "CAD" to 1.87425,
        "CHF" to 1.09768,
        "CNY" to 8.89662,
        "CZK" to 28.2933,
        "DKK" to 8.6879,
        "HKD" to 10.3951,
        "HUF" to 424.522,
        "IDR" to 23740.2,
        "ILS" to 4.02045,
        "INR" to 126.981,
        "ISK" to 158.754,
        "JPY" to 208.844,
        "KRW" to 1795.76,
        "MXN" to 23.4547,
        "MYR" to 5.39904,
        "NOK" to 12.5981,
        "NZD" to 2.33692,
        "PHP" to 82.7985,
        "PLN" to 5.08083,
        "RON" to 6.13226,
        "SEK" to 13.121,
        "SGD" to 1.69249,
        "THB" to 44.1897,
        "TRY" to 64.8469,
        "ZAR" to 21.5931,
    )

    val currencies: List<String> = listOf("GBP", "EUR", "USD") + perPound.keys.filter { it !in setOf("GBP", "EUR", "USD") }.sorted()

    fun convert(amount: Double, from: String, to: String): Double? {
        if (from == to) return amount
        val source = perPound[from] ?: return null
        val target = perPound[to] ?: return null
        return amount / source * target
    }
}
