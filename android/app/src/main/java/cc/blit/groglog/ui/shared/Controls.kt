package cc.blit.groglog.ui.shared

import android.text.format.DateFormat
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.InputTransformation
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.byValue
import androidx.compose.foundation.text.input.placeCursorAtEnd
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.money
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.text.DecimalFormatSymbols
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Currency
import kotlin.math.pow

/** The inset form rows share, so labels line up down a sheet. */
val RowPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp)

/**
 * Chips for picking one of a few values, wrapping onto further lines as iOS's do, so none is hidden off the edge. An unavailable option stays on the row, greyed out: removing it
 * would leave a gap that reads as a missing feature, with no indication of what the option was. `tint` colours the
 * selected chip, for a row that also serves as a chart's key.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun <T> ChipRow(
    options: List<T>,
    selected: T,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    isEnabled: (T) -> Boolean = { true },
    tint: ((T) -> Color)? = null,
    label: (T) -> String,
) {
    FlowRow(
        modifier.fillMaxWidth().padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        for (option in options) {
            val isSelected = option == selected
            FilterChip(
                selected = isSelected,
                onClick = { onSelect(option) },
                enabled = isEnabled(option),
                label = { Text(label(option), fontWeight = if (isSelected) FontWeight.SemiBold else null) },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = tint?.let { it(option).copy(alpha = 0.24f) } ?: MaterialTheme.colorScheme.secondaryContainer),
            )
        }
    }
}

/**
 * A labelled decimal field with a unit suffix, over a `TextFieldState` its owner holds and reads with `parseDecimal`.
 * Typing is limited to digits and one decimal separator, the reader's or a full stop. `error` is shown beneath, for a
 * figure that is empty or out of range, which the owner refuses rather than saving a figure it did not mean.
 * `onEditingEnded` is for anything that reacts to the value by changing something else: halfway through typing "30" the
 * value is 3, and acting on that interferes with the typing.
 */
@Composable
fun NumberRow(
    label: String,
    state: TextFieldState,
    suffix: String,
    modifier: Modifier = Modifier,
    error: String? = null,
    onEditingEnded: () -> Unit = {},
) {
    var focused by remember { mutableStateOf(false) }
    val focus = LocalFocusManager.current
    Column(modifier.keptAboveKeyboard(focused)) {
        FormRow(label) {
            BasicTextField(
                state = state,
                modifier = Modifier
                    .width(FieldWidth)
                    .semantics {
                        contentDescription = label
                        if (error != null) error(error)
                    }
                    .onFocusChanged {
                        if (focused && !it.isFocused) onEditingEnded()
                        focused = it.isFocused
                    },
                inputTransformation = DecimalInput,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface, textAlign = TextAlign.End),
                lineLimits = TextFieldLineLimits.SingleLine,
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
                onKeyboardAction = { focus.clearFocus() },
                decorator = { field ->
                    FieldFrame(isError = error != null) {
                        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) { field() }
                        Text(suffix, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp))
                    }
                },
            )
        }
        if (error != null) {
            Text(
                error,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 4.dp),
            )
        }
    }
}

/** Digits and one decimal mark, whichever of a full stop, a comma or the reader's own was typed. */
private val DecimalInput = InputTransformation.byValue { current, proposed ->
    val valid = proposed.all { it.isDigit() || it.isDecimalMark() } && proposed.count { it.isDecimalMark() } <= 1 && proposed.length <= 8
    if (valid) proposed else current
}

private fun Char.isDecimalMark() = this == '.' || this == ',' || this == DecimalFormatSymbols.getInstance().decimalSeparator

/**
 * Reads a typed decimal with a full stop, a comma or the reader's own mark, or null if it is not a number. Grouping is
 * never typed into these fields, so a comma is always the decimal mark: "5,2" is five point two.
 */
fun parseDecimal(text: CharSequence): Double? {
    val normal = text.toString().trim().map { if (it.isDecimalMark()) '.' else it }.joinToString("")
    return normal.takeIf { it.isNotEmpty() && it != "." }?.toDoubleOrNull()
}

/** A figure as a field starts out showing it: no trailing zeros, no grouping, in the reader's notation. */
fun decimalText(value: Double, maxDigits: Int = 2): String =
    NumberFormat.getNumberInstance().apply {
        isGroupingUsed = false
        maximumFractionDigits = maxDigits
    }.format(value)

/** Digits per whole unit of a currency: 100 for pence and cents, 1 for yen and won, which have no minor unit. */
private fun minorUnits(currency: String): Double =
    10.0.pow(runCatching { Currency.getInstance(currency).defaultFractionDigits }.getOrNull()?.coerceAtLeast(0) ?: 2)

/** The digits a `MoneyField` holds for an amount. */
fun moneyDigits(amount: Double, currency: String): String = Math.round(amount * minorUnits(currency)).toString()

/** The amount a `MoneyField`'s digits stand for. Empty is nothing, since a drink can be free. */
fun moneyValue(digits: CharSequence, currency: String): Double = (digits.toString().toLongOrNull() ?: 0L) / minorUnits(currency)

/**
 * Money entered as banking apps take it: digits only, filling from the pence up, so typing 1, 5, 0 reads £0.01, £0.15,
 * £1.50. The state holds the digits (`moneyDigits`, `moneyValue`); the field shows them as money. Wherever the cursor
 * is, a digit typed or pasted shifts in at the end and a backspace takes the last one off, as on a card terminal.
 */
@Composable
fun MoneyField(label: String, state: TextFieldState, currency: String, modifier: Modifier = Modifier) {
    val focus = LocalFocusManager.current
    var focused by remember { mutableStateOf(false) }
    val shown = moneyValue(state.text, currency).money(currency)
    FormRow(label, modifier.keptAboveKeyboard(focused)) {
        BasicTextField(
            state = state,
            modifier = Modifier
                .width(FieldWidth)
                .semantics { contentDescription = "$label, $shown" }
                .onFocusChanged { focused = it.isFocused },
            inputTransformation = MoneyInput,
            lineLimits = TextFieldLineLimits.SingleLine,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
            onKeyboardAction = { focus.clearFocus() },
            decorator = { field ->
                // The digits field takes the keystrokes unseen; what shows is the amount they make.
                FieldFrame {
                    Text(shown, style = MaterialTheme.typography.bodyLarge, color = if (focused) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface)
                    Box(Modifier.alpha(0f).width(0.dp)) { field() }
                }
            },
        )
    }
}

/** Applies an edit to a money field's digits as a terminal would: what was typed goes on the end, what was deleted comes off it. */
private val MoneyInput = InputTransformation {
    val edited = moneyEdit(originalText.toString(), asCharSequence().toString())
    replace(0, length, edited)
    placeCursorAtEnd()
}

/**
 * The digits after an edit that turned `before` into `after`, wherever in the field it happened: inserted digits are
 * appended, each deleted character removes the last digit, and anything that is not a digit is dropped. At most nine
 * digits, without leading zeros.
 */
internal fun moneyEdit(before: String, after: String): String {
    var prefix = 0
    while (prefix < before.length && prefix < after.length && before[prefix] == after[prefix]) prefix++
    var suffix = 0
    while (suffix < before.length - prefix && suffix < after.length - prefix &&
        before[before.length - 1 - suffix] == after[after.length - 1 - suffix]
    ) suffix++
    val deleted = before.length - prefix - suffix
    val inserted = after.substring(prefix, after.length - suffix).filter(Char::isDigit)
    return (before.dropLast(deleted) + inserted).trimStart('0').take(9)
}

/** A clock time within a drinking day: 01:30 lands after midnight rather than before the day began. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimeRow(label: String, time: Instant, onTimeChange: (Instant) -> Unit, clock: DayClock, day: DayKey, modifier: Modifier = Modifier) {
    var picking by rememberSaveable { mutableStateOf(false) }
    val local = time.atZone(clock.zone).toLocalTime()
    val shown = local.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))
    FormRow(label, modifier) {
        TextButton(onClick = { picking = true }, modifier = Modifier.semantics { contentDescription = "$label, $shown" }) {
            Text(shown, style = MaterialTheme.typography.bodyLarge)
        }
    }
    if (picking) {
        val state = rememberTimePickerState(local.hour, local.minute, DateFormat.is24HourFormat(LocalContext.current))
        AlertDialog(
            onDismissRequest = { picking = false },
            confirmButton = {
                TextButton(onClick = {
                    val chosen = time.atZone(clock.zone).with(LocalTime.of(state.hour, state.minute)).toInstant()
                    onTimeChange(clock.resolve(chosen, day))
                    picking = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { picking = false }) { Text("Cancel") } },
            text = { TimePicker(state) },
        )
    }
}

/** A count between bounds, with a button either side. */
@Composable
fun StepperRow(label: String, value: Int, onValueChange: (Int) -> Unit, range: IntRange, modifier: Modifier = Modifier) {
    FormRow(label, modifier) {
        FilledTonalIconButton(onClick = { onValueChange(value - 1) }, enabled = value > range.first) {
            Icon(GrogIcons.Remove, contentDescription = "Fewer")
        }
        FilledTonalIconButton(onClick = { onValueChange(value + 1) }, enabled = value < range.last) {
            Icon(Icons.Filled.Add, contentDescription = "More")
        }
    }
}

/** A label on the left and its control on the right, at least a touch target tall. */
@Composable
fun FormRow(label: String, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable () -> Unit) {
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(RowPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        content()
    }
}

/**
 * While a field is focused, keeps its whole row in view as the keyboard rises: the text field alone asks for its own
 * bounds once, before the keyboard has finished opening, and ends up half hidden.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Modifier.keptAboveKeyboard(focused: Boolean): Modifier {
    val requester = remember { BringIntoViewRequester() }
    val keyboard = WindowInsets.ime.getBottom(LocalDensity.current)
    LaunchedEffect(focused, keyboard) { if (focused) requester.bringIntoView() }
    return bringIntoViewRequester(requester)
}

/** Every field's width, so the right edges of a sheet's figures line up. */
private val FieldWidth = 140.dp

@Composable
private fun FieldFrame(isError: Boolean = false, content: @Composable RowScope.() -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .border(1.dp, if (isError) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(10.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

@Preview(showBackground = true)
@Composable
private fun ControlsPreview() {
    GrogLogTheme {
        Surface {
            Column {
                ChipRow(listOf("Pint", "Half", "440 ml can"), "Pint", {}) { it }
                NumberRow("Strength", rememberTextFieldState("4.6"), "% ABV")
                NumberRow("Size", rememberTextFieldState(""), "ml", error = "Enter a size.")
                MoneyField("Price", rememberTextFieldState("650"), "GBP")
                StepperRow("How many: 2", 2, {}, 1..12)
                TimeRow("At", Instant.now(), {}, DayClock(5), DayClock(5).today)
            }
        }
    }
}
