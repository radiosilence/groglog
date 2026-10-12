package cc.blit.groglog.ui.shared

import android.text.format.DateFormat
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.money
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Currency
import kotlin.math.pow
import kotlin.math.roundToLong

/** The inset form rows share, so labels line up down a sheet. */
val RowPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp)

/**
 * A row of chips for picking one of a few values. An unavailable option stays on the row, greyed out: removing it
 * would leave a gap that reads as a missing feature, with no indication of what the option was. `tint` colours the
 * selected chip, for a row that also serves as a chart's key.
 */
@Composable
fun <T> ChipRow(
    options: List<T>,
    selected: T,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    isEnabled: (T) -> Boolean = { true },
    tint: (T) -> Color = { GrogColors.grog },
    label: (T) -> String,
) {
    LazyRow(
        modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(options) { option ->
            val isSelected = option == selected
            FilterChip(
                selected = isSelected,
                onClick = { onSelect(option) },
                enabled = isEnabled(option),
                label = { Text(label(option), fontWeight = if (isSelected) FontWeight.SemiBold else null) },
                colors = FilterChipDefaults.filterChipColors(selectedContainerColor = tint(option).copy(alpha = 0.24f)),
            )
        }
    }
}

/**
 * A labelled decimal field with a unit suffix. While focused the field keeps what was typed, so "3" on the way to "30"
 * is not reformatted under the cursor. `onEditingEnded` is for anything that reacts to the value by changing something
 * else: halfway through typing "30" the value is 3, and acting on that interferes with the typing.
 */
@Composable
fun NumberRow(
    label: String,
    value: Double,
    onValueChange: (Double) -> Unit,
    suffix: String,
    modifier: Modifier = Modifier,
    onEditingEnded: () -> Unit = {},
) {
    var typed by remember { mutableStateOf<String?>(null) }
    val focus = LocalFocusManager.current
    FormRow(label, modifier) {
        BasicTextField(
            value = typed ?: decimal.format(value),
            onValueChange = { text ->
                typed = text
                text.replace(',', '.').toDoubleOrNull()?.let(onValueChange)
            },
            modifier = Modifier
                .widthIn(min = 56.dp, max = 120.dp)
                .semantics { contentDescription = label }
                .onFocusChanged {
                    if (!it.isFocused && typed != null) {
                        typed = null
                        onEditingEnded()
                    }
                },
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface, textAlign = TextAlign.End),
            singleLine = true,
            cursorBrush = SolidColor(GrogColors.grog),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { focus.clearFocus() }),
            decorationBox = { FieldFrame(it) },
        )
        Text(suffix, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp))
    }
}

/**
 * Money entered like a banking app: digits only, filling from the pence up, so typing 1, 5, 0 reads £0.01, £0.15,
 * £1.50. A hidden digits field takes the keystrokes; the label shows them as money.
 */
@Composable
fun MoneyField(label: String, value: Double, onValueChange: (Double) -> Unit, currency: String, modifier: Modifier = Modifier) {
    // Digits per whole unit of the currency: 100 for pence and cents, 1 for yen and won, which have no minor unit.
    val scale = 10.0.pow(runCatching { Currency.getInstance(currency).defaultFractionDigits }.getOrDefault(2).coerceAtLeast(0))
    var typed by remember { mutableStateOf<String?>(null) }
    var focused by remember { mutableStateOf(false) }
    val digits = typed ?: (value * scale).roundToLong().toString()
    val shown = ((digits.toLongOrNull() ?: 0) / scale).money(currency)
    val focus = LocalFocusManager.current
    FormRow(label, modifier) {
        BasicTextField(
            value = digits,
            onValueChange = { text ->
                val clean = text.filter(Char::isDigit).take(9)
                typed = clean
                onValueChange((clean.toLongOrNull() ?: 0) / scale)
            },
            modifier = Modifier
                .semantics { contentDescription = "$label, $shown" }
                .onFocusChanged {
                    focused = it.isFocused
                    if (!it.isFocused) typed = null
                },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { focus.clearFocus() }),
            decorationBox = { field ->
                FieldFrame {
                    Box(contentAlignment = Alignment.CenterEnd) {
                        Text(
                            shown,
                            style = MaterialTheme.typography.bodyLarge,
                            color = if (focused) GrogColors.grog else MaterialTheme.colorScheme.onSurface,
                        )
                        Box(Modifier.alpha(0f)) { field() }
                    }
                }
            },
        )
    }
}

/** A clock time within a drinking day: 01:30 lands after midnight rather than before the day began. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimeRow(label: String, time: Instant, onTimeChange: (Instant) -> Unit, clock: DayClock, day: DayKey, modifier: Modifier = Modifier) {
    var picking by remember { mutableStateOf(false) }
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

@Composable
private fun FieldFrame(field: @Composable () -> Unit) {
    Box(
        Modifier
            .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(10.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        contentAlignment = Alignment.CenterEnd,
    ) { field() }
}

private val decimal: NumberFormat
    get() = NumberFormat.getNumberInstance().apply {
        maximumFractionDigits = 2
        isGroupingUsed = false
    }

@Preview(showBackground = true)
@Composable
private fun ControlsPreview() {
    GrogLogTheme {
        Surface {
            Column {
                ChipRow(listOf("Pint", "Half", "440 ml can"), "Pint", {}) { it }
                NumberRow("Strength", 4.6, {}, "% ABV")
                MoneyField("Price", 6.5, {}, "GBP")
                StepperRow("How many: 2", 2, {}, 1..12)
                TimeRow("At", Instant.now(), {}, DayClock(5), DayClock(5).today)
            }
        }
    }
}
