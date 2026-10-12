package cc.blit.groglog.ui.log

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Settings
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.ServeSize
import cc.blit.groglog.model.Units
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.containerViewModel
import cc.blit.groglog.ui.shared.ChipRow
import cc.blit.groglog.ui.shared.DrinkGlyph
import cc.blit.groglog.ui.shared.MoneyField
import cc.blit.groglog.ui.shared.NumberRow
import cc.blit.groglog.ui.shared.TimeRow
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.time.Instant
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Writes for `PourEditor`. */
class PourEditorViewModel(prefs: Prefs, private val logbook: suspend () -> Logbook) : ViewModel() {
    val settings: StateFlow<Settings?> = prefs.settings.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    fun save(pour: Pour, time: Instant, vessel: Vessel, volumeMl: Double, price: Double, abvOverride: Double?) {
        viewModelScope.launch { logbook().update(pour, time, vessel, volumeMl, price, abvOverride) }
    }

    fun delete(pour: Pour) {
        viewModelScope.launch { logbook().delete(pour) }
    }

}

/**
 * One logged drink: when, how much, what it cost, and its strength this time. Name and type belong to the drink, edited
 * through `onEditDrink`. Works on a draft saved on Done.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PourEditor(
    entry: Entry,
    day: DayKey,
    onDismiss: () -> Unit,
    onEditDrink: ((Drink) -> Unit)? = null,
    viewModel: PourEditorViewModel = containerViewModel { PourEditorViewModel(it.prefs, it::logbook) },
) {
    val settings by viewModel.settings.collectAsStateWithLifecycle()
    val loaded = settings ?: return
    ModalBottomSheet(onDismissRequest = onDismiss) {
        PourForm(
            entry = entry,
            day = day,
            clock = loaded.clock,
            currency = loaded.currency,
            onDismiss = onDismiss,
            onEditDrink = onEditDrink,
            onSave = { time, vessel, volume, price, abv -> viewModel.save(entry.pour, time, vessel, volume, price, abv) },
            onDelete = { viewModel.delete(entry.pour) },
        )
    }
}

@Composable
private fun PourForm(
    entry: Entry,
    day: DayKey,
    clock: DayClock,
    currency: String,
    onDismiss: () -> Unit,
    onEditDrink: ((Drink) -> Unit)?,
    onSave: (time: Instant, vessel: Vessel, volumeMl: Double, price: Double, abvOverride: Double?) -> Unit,
    onDelete: () -> Unit,
) {
    val isUnits = entry.category == DrinkCategory.UNITS
    var time by remember { mutableStateOf(entry.timestamp) }
    var vessel by remember { mutableStateOf(entry.vessel) }
    var volume by remember { mutableStateOf(entry.volumeMl) }
    var price by remember { mutableStateOf(entry.price) }
    var abv by remember { mutableStateOf(entry.abv) }
    val valid = isUnits || Units.isStrength(abv)

    Column(Modifier.imePadding().verticalScroll(rememberScrollState()).padding(bottom = 16.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDismiss) { Text("Cancel") }
            Text("Drink", Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            Button(
                onClick = {
                    onSave(time, vessel, volume, price, if (isUnits || abv == entry.drink.abv) null else abv)
                    onDismiss()
                },
                enabled = valid,
            ) { Text("Done") }
        }
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            DrinkGlyph(entry.category, vessel, Modifier.size(56.dp), volumeMl = volume)
            Column {
                Text(entry.name, style = MaterialTheme.typography.titleMedium)
                Text("${Units.of(volume, abv).unitsText} u", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (!isUnits && onEditDrink != null) {
            TextButton(onClick = { onEditDrink(entry.drink) }, Modifier.padding(horizontal = 8.dp)) {
                Icon(Icons.Filled.Edit, contentDescription = null, Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("Edit ${entry.name}")
            }
        }
        HorizontalDivider(Modifier.padding(vertical = 8.dp))
        TimeRow("Time", time, { time = it }, clock, day)
        if (isUnits) {
            NumberRow("Units", volume / 10, { volume = it * 10 }, "u")
        } else {
            val size = ServeSize(vessel, volume)
            ChipRow(entry.drink.sizes(size), size, {
                vessel = it.vessel
                volume = it.ml
            }, Modifier.padding(vertical = 8.dp)) { it.label }
            NumberRow("Size", volume, { volume = it }, "ml")
            NumberRow("Strength", abv, { abv = it }, "% ABV")
        }
        MoneyField("Price", price, { price = it }, currency)
        HorizontalDivider(Modifier.padding(vertical = 8.dp))
        TextButton(
            onClick = {
                onDelete()
                onDismiss()
            },
            colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
            modifier = Modifier.padding(horizontal = 8.dp),
        ) {
            Icon(Icons.Filled.Delete, contentDescription = null, Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Delete")
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun PourFormPreview() {
    val clock = DayClock(5)
    val drink = Drink(name = "Staropramen", category = DrinkCategory.BEER, abv = 5.0, vessel = Vessel.PINT, volumeMl = 568.0, price = 6.5)
    val pour = Pour(drinkId = drink.id, timestamp = Instant.now(), day = clock.today.number, vessel = Vessel.PINT, volumeMl = 568.0, price = 6.5)
    GrogLogTheme {
        Surface { PourForm(Entry(pour, drink), clock.today, clock, "GBP", {}, {}, { _, _, _, _, _ -> }, {}) }
    }
}
