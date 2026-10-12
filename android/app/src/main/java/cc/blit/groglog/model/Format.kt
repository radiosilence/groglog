package cc.blit.groglog.model

import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

private fun decimals(min: Int, max: Int, locale: Locale = Locale.getDefault()) =
    NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = min
        maximumFractionDigits = max
    }

val Double.unitsText: String get() = decimals(1, 1).format(this)

val Double.kcalText: String get() = NumberFormat.getIntegerInstance().format(Math.round(this))

fun Double.money(currency: String): String {
    val format = NumberFormat.getCurrencyInstance()
    runCatching { Currency.getInstance(currency) }.getOrNull()?.let {
        format.currency = it
        format.minimumFractionDigits = it.defaultFractionDigits.coerceAtLeast(0)
        format.maximumFractionDigits = it.defaultFractionDigits.coerceAtLeast(0)
    }
    return format.format(this)
}

val Double.volumeText: String get() = "${toInt()} ml"

val Double.abvText: String get() = "${decimals(0, 1).format(this)}%"

/**
 * What remains of a budget with this much used, or how far past it: "2.5 of 4.5 left", "1.3 over 4.5". An overrun
 * reads as an amount over, never as a negative amount left.
 */
fun Double.leftText(budget: Double): String {
    val left = budget - this
    return if (left >= 0) "${left.unitsText} of ${budget.unitsText} left" else "${(-left).unitsText} over ${budget.unitsText}"
}
