package cc.blit.groglog.ui.day

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.model.money
import java.util.Currency
import kotlin.math.pow
import kotlin.math.roundToLong

// Stand-ins for components the Log and Setup tabs own (ui/shared and the drink picker). Each has the shape its owner
// is expected to provide, so swapping one is a change of import.

/** Stand-in for ui/shared's DrinkGlyph: a glass filled with the drink's colour. */
@Composable
internal fun DrinkGlyph(category: DrinkCategory, vessel: Vessel, volumeMl: Double, modifier: Modifier = Modifier) {
    val liquid = Color(category.liquid)
    val outline = MaterialTheme.colorScheme.onSurfaceVariant
    Canvas(modifier) {
        val glass = Size(size.width * 0.56f, size.height * 0.78f)
        val topLeft = Offset((size.width - glass.width) / 2, (size.height - glass.height) / 2)
        val fill = glass.height * 0.72f
        drawRoundRect(liquid, topLeft + Offset(0f, glass.height - fill), Size(glass.width, fill), CornerRadius(6.dp.toPx()))
        drawRoundRect(outline, topLeft, glass, CornerRadius(6.dp.toPx()), style = Stroke(1.5.dp.toPx()))
    }
}

/** Stand-in for the Log tab's picker, opened for backfilling a day. */
@Composable
internal fun AddDrinksSheet(day: DayKey, onDismiss: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("The drink picker for $day")
        TextButton(onClick = onDismiss) { Text("Done") }
    }
}

/** Stand-in for ui/shared's ChipRow: a row of pills for picking one of a few values. */
@Composable
internal fun <T> ChipRow(options: List<T>, selection: T, onSelect: (T) -> Unit, label: (T) -> String, modifier: Modifier = Modifier) {
    Row(modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (option in options) {
            FilterChip(selected = option == selection, onClick = { onSelect(option) }, label = { Text(label(option)) })
        }
    }
}

/** Stand-in for ui/shared's NumberRow: a labelled decimal field with a unit suffix. */
@Composable
internal fun NumberRow(label: String, value: Double, onValueChange: (Double) -> Unit, suffix: String, modifier: Modifier = Modifier) {
    var text by rememberSaveable { mutableStateOf(decimal(value)) }
    OutlinedTextField(
        value = text,
        onValueChange = { typed ->
            text = typed
            typed.replace(',', '.').toDoubleOrNull()?.let(onValueChange)
        },
        label = { Text(label) },
        suffix = { Text(suffix) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        modifier = modifier.fillMaxWidth(),
    )
}

private fun decimal(value: Double) = if (value % 1.0 == 0.0) value.toLong().toString() else value.toString()

/**
 * Stand-in for ui/shared's MoneyField. Money entered like a banking app: digits only, filling from the pence up, so
 * typing 1, 5, 0 reads £0.01, £0.15, £1.50.
 */
@Composable
internal fun MoneyField(label: String, value: Double, onValueChange: (Double) -> Unit, currency: String, modifier: Modifier = Modifier) {
    val scale = 10.0.pow(runCatching { Currency.getInstance(currency).defaultFractionDigits }.getOrDefault(2).coerceAtLeast(0))
    var digits by rememberSaveable { mutableStateOf((value * scale).roundToLong().toString()) }
    OutlinedTextField(
        value = digits,
        onValueChange = { typed ->
            digits = typed.filter(Char::isDigit).take(9).trimStart('0')
            onValueChange((digits.toLongOrNull() ?: 0) / scale)
        },
        label = { Text(label) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
        visualTransformation = { text ->
            val shown = ((text.text.toLongOrNull() ?: 0) / scale).money(currency)
            TransformedText(AnnotatedString(shown), object : OffsetMapping {
                override fun originalToTransformed(offset: Int) = shown.length
                override fun transformedToOriginal(offset: Int) = text.length
            })
        },
        modifier = modifier.fillMaxWidth(),
    )
}
