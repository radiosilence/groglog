package cc.blit.groglog.export

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.util.Locale
import kotlin.math.abs
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * JSON laid out byte for byte as iOS's `JSONEncoder` writes it with `.prettyPrinted`, `.sortedKeys` and
 * `.withoutEscapingSlashes`, so a backup reads the same whichever phone wrote it: two-space indents, `"key" : value`,
 * empty containers split over two lines, numbers in their shortest form with whole numbers bare, and only quotes,
 * backslashes and control characters escaped.
 */
object SwiftJson {
    fun encode(element: JsonElement): String = StringBuilder().also { write(element, it, "") }.toString()

    private fun write(element: JsonElement, out: StringBuilder, indent: String) {
        val inner = "$indent  "
        when (element) {
            is JsonObject -> {
                out.append("{\n")
                val keys = element.keys.sorted()
                keys.forEachIndexed { index, key ->
                    out.append(inner)
                    string(key, out)
                    out.append(" : ")
                    write(element.getValue(key), out, inner)
                    if (index < keys.size - 1) out.append(',')
                    out.append('\n')
                }
                if (keys.isEmpty()) out.append('\n')
                out.append(indent).append('}')
            }
            is JsonArray -> {
                out.append("[\n")
                element.forEachIndexed { index, item ->
                    out.append(inner)
                    write(item, out, inner)
                    if (index < element.size - 1) out.append(',')
                    out.append('\n')
                }
                if (element.isEmpty()) out.append('\n')
                out.append(indent).append(']')
            }
            JsonNull -> out.append("null")
            is JsonPrimitive -> when {
                element.isString -> string(element.content, out)
                element.content == "true" || element.content == "false" -> out.append(element.content)
                element.content.any { it == '.' || it == 'e' || it == 'E' } -> out.append(number(element.content.toDouble()))
                else -> out.append(element.content)
            }
        }
    }

    private fun string(value: String, out: StringBuilder) {
        out.append('"')
        for (c in value) {
            when (c) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                '\b' -> out.append("\\b")
                '\u000C' -> out.append("\\f")
                else -> if (c < ' ') out.append(String.format(Locale.ROOT, "\\u%04x", c.code)) else out.append(c)
            }
        }
        out.append('"')
    }

    /**
     * Swift's `description` of a `Double`: the shortest digits that read back as the same value, plain from 1e-4 up to
     * 1e16 and in exponent form outside it, with a whole number written without a fraction.
     */
    fun number(value: Double): String {
        require(value.isFinite()) { "JSON has no form for $value" }
        if (value == 0.0) return if (1 / value < 0) "-0" else "0"
        val exact = BigDecimal(value)
        var shortest = exact
        for (digits in 1..17) {
            shortest = exact.round(MathContext(digits, RoundingMode.HALF_EVEN))
            if (shortest.toDouble() == value) break
        }
        shortest = shortest.stripTrailingZeros()
        val exponent = shortest.precision() - shortest.scale() - 1
        if (exponent in -4..15) return shortest.toPlainString()
        val digits = shortest.unscaledValue().abs().toString()
        val mantissa = if (digits.length > 1) "${digits[0]}.${digits.substring(1)}" else digits
        val sign = if (shortest.signum() < 0) "-" else ""
        return "$sign${mantissa}e${if (exponent < 0) "-" else "+"}${String.format(Locale.ROOT, "%02d", abs(exponent))}"
    }
}
