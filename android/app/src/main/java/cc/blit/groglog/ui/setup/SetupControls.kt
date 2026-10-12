package cc.blit.groglog.ui.setup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.InputTransformation
import androidx.compose.foundation.text.input.OutputTransformation
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.byValue
import androidx.compose.foundation.text.input.maxLength
import androidx.compose.foundation.text.input.then
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.money
import java.text.DecimalFormatSymbols
import java.text.NumberFormat
import java.util.Currency
import kotlin.math.pow

/** A titled group of rows on a rounded surface, with an optional note beneath, as Android's own settings lay them out. */
@Composable
internal fun SettingsSection(
    modifier: Modifier = Modifier,
    title: String? = null,
    footer: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
        if (title != null) {
            Text(
                title,
                // Not the primary colour: GrogLog's amber is too light to read as small text on a light background.
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, bottom = 8.dp).semantics { heading() },
            )
        }
        Surface(
            shape = RoundedCornerShape(20.dp),
            color = MaterialTheme.colorScheme.surfaceContainerLow,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(content = content)
        }
        if (footer != null) {
            Text(
                footer,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp),
            )
        }
    }
}

/**
 * Pick one of a few values. An unavailable option stays in place, greyed out: removing it would leave a gap that reads
 * as a missing feature, with no sign of what the option was.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun <T> ChipRow(
    options: List<T>,
    selected: T,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    isEnabled: (T) -> Boolean = { true },
    label: (T) -> String,
) {
    FlowRow(
        modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        for (option in options) {
            FilterChip(
                selected = option == selected,
                onClick = { onSelect(option) },
                label = { Text(label(option)) },
                enabled = isEnabled(option),
            )
        }
    }
}

/**
 * A decimal field with its unit as a suffix. `onEditingEnded` runs when focus leaves: anything that reacts to the value
 * by changing something else belongs there, since halfway through typing "30" the value is 3.
 */
@Composable
internal fun NumberField(
    label: String,
    state: TextFieldState,
    suffix: String,
    modifier: Modifier = Modifier,
    onEditingEnded: () -> Unit = {},
    error: String? = null,
) {
    var focused by remember { mutableStateOf(false) }
    OutlinedTextField(
        state = state,
        label = { Text(label) },
        suffix = { Text(suffix) },
        isError = error != null,
        supportingText = error?.let { { Text(it) } },
        inputTransformation = DecimalInput,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
        lineLimits = androidx.compose.foundation.text.input.TextFieldLineLimits.SingleLine,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp)
            .onFocusChanged {
                if (focused && !it.isFocused) onEditingEnded()
                focused = it.isFocused
            },
    )
}

/** Digits and one decimal separator, either the reader's or a full stop. */
private val DecimalInput = InputTransformation.byValue { current, proposed ->
    val separator = DecimalFormatSymbols.getInstance().decimalSeparator
    val valid = proposed.all { it.isDigit() || it == '.' || it == separator } &&
        proposed.count { it == '.' || it == separator } <= 1 && proposed.length <= 8
    if (valid) proposed else current
}

/** Reads a typed decimal in the reader's notation or with a full stop, or null if it is not a number. */
internal fun parseDecimal(text: CharSequence): Double? {
    val separator = DecimalFormatSymbols.getInstance().decimalSeparator
    return text.toString().trim().replace(separator, '.').takeIf { it.isNotEmpty() && it != "." }?.toDoubleOrNull()
}

/** A figure as a field starts out showing it: no trailing zeros, in the reader's notation. */
internal fun decimalText(value: Double, maxDigits: Int = 2): String =
    NumberFormat.getNumberInstance().apply {
        isGroupingUsed = false
        maximumFractionDigits = maxDigits
    }.format(value)

/** Digits per whole unit of a currency: 100 for pence and cents, 1 for yen and won, which have no minor unit. */
internal fun minorUnits(currency: String): Double =
    10.0.pow(runCatching { Currency.getInstance(currency).defaultFractionDigits }.getOrNull()?.coerceAtLeast(0) ?: 2)

/** The digits a `MoneyField` holds for an amount. */
internal fun moneyDigits(amount: Double, currency: String): String = Math.round(amount * minorUnits(currency)).toString()

/** The amount a `MoneyField`'s digits stand for. */
internal fun moneyValue(digits: CharSequence, currency: String): Double = (digits.toString().toLongOrNull() ?: 0L) / minorUnits(currency)

/**
 * Money entered as banking apps take it: digits only, filling from the pence up, so typing 1, 5, 0 reads £0.01, £0.15,
 * £1.50. The state holds the digits; the field shows them as money.
 */
@Composable
internal fun MoneyField(label: String, state: TextFieldState, currency: String, modifier: Modifier = Modifier) {
    OutlinedTextField(
        state = state,
        label = { Text(label) },
        inputTransformation = InputTransformation.byValue { current, proposed ->
            if (proposed.all { it.isDigit() }) proposed else current
        }.then(InputTransformation.maxLength(9)),
        outputTransformation = OutputTransformation {
            val shown = moneyValue(asCharSequence(), currency).money(currency)
            replace(0, length, shown)
        },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
        lineLimits = androidx.compose.foundation.text.input.TextFieldLineLimits.SingleLine,
        modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
    )
}
