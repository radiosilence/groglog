package cc.blit.groglog.ui.day

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.model.Drink
import androidx.compose.ui.graphics.Color
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.money
import java.util.Currency
import kotlin.math.pow
import kotlin.math.roundToLong

// Stand-ins for what the Log tab provides on origin/android-log: ui/shared's ChipRow, NumberRow and MoneyField, and
// ui/log's AddDrinkSheet and PourEditor. Each has its real signature, so at merge this file and PourEditor.kt's
// PourEditor go and the imports change.

/** Stand-in for ui/log's AddDrinkSheet: the picker for backfilling a day. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AddDrinkSheet(day: DayKey, onDismiss: () -> Unit, onCreateDrink: ((String) -> Unit)? = null, onEditDrink: ((Drink) -> Unit)? = null) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("The drink picker for $day")
            TextButton(onClick = onDismiss) { Text("Done") }
        }
    }
}

/** Stand-in for ui/shared's ChipRow: a row of pills for picking one of a few values. */
@Composable
internal fun <T> ChipRow(
    options: List<T>,
    selected: T,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    isEnabled: (T) -> Boolean = { true },
    tint: (T) -> Color = { GrogColors.grog },
    label: (T) -> String,
) {
    Row(modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (option in options) {
            FilterChip(selected = option == selected, onClick = { onSelect(option) }, label = { Text(label(option)) }, enabled = isEnabled(option), colors = FilterChipDefaults.filterChipColors(selectedContainerColor = tint(option).copy(alpha = 0.3f)))
        }
    }
}

/** Stand-in for ui/shared's NumberRow: a labelled decimal field with a unit suffix. */
@Composable
internal fun NumberRow(label: String, value: Double, onValueChange: (Double) -> Unit, suffix: String, modifier: Modifier = Modifier, onEditingEnded: () -> Unit = {}) {
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
