package cc.blit.groglog.ui.day

import android.text.format.DateFormat
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.ServeSize
import cc.blit.groglog.model.Units
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.model.money
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.shared.DrinkGlyph
import java.time.Instant
import java.time.LocalDateTime
import java.time.LocalTime
import java.util.Date

/**
 * One logged drink: when, how much, what it cost. Name and strength belong to the drink. Works on a draft saved on
 * Done.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun PourEditor(
    entry: Entry,
    day: DayKey,
    clock: DayClock,
    currency: String,
    onDone: (time: Instant, vessel: Vessel, volumeMl: Double, price: Double, abvOverride: Double?) -> Unit,
    onDelete: () -> Unit,
    onDismiss: () -> Unit,
) {
    val isUnits = entry.category == DrinkCategory.UNITS
    var time by rememberSaveable { mutableLongStateOf(entry.timestamp.toEpochMilli()) }
    var vessel by rememberSaveable { mutableStateOf(entry.vessel) }
    var volume by rememberSaveable { mutableDoubleStateOf(entry.volumeMl) }
    var price by rememberSaveable { mutableDoubleStateOf(entry.price) }
    var abv by rememberSaveable { mutableDoubleStateOf(entry.abv) }
    var pickingTime by rememberSaveable { mutableStateOf(false) }
    var sizePicks by rememberSaveable { mutableIntStateOf(0) }
    val context = LocalContext.current
    val valid = isUnits || Units.isStrength(abv)

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                DrinkGlyph(entry.category, vessel, Modifier.size(56.dp), volume)
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(entry.name, style = MaterialTheme.typography.titleMedium)
                    Text(
                        "${Units.of(volume, abv).unitsText} u",
                        style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            ListItem(
                headlineContent = { Text("Time") },
                trailingContent = {
                    Text(DateFormat.getTimeFormat(context).format(Date(time)), style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"))
                },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                modifier = Modifier.clickable(onClickLabel = "Change the time") { pickingTime = true },
            )
            if (isUnits) {
                NumberRow("Units", volume / 10, { volume = it * 10 }, "u")
            } else {
                val size = ServeSize(vessel, volume)
                ChipRow(entry.drink.sizes(size), size, {
                    vessel = it.vessel
                    volume = it.ml
                    sizePicks += 1
                }, { it.label })
                // Started afresh when a chip is picked, so it shows that size rather than what was typed before.
                key(sizePicks) { NumberRow("Size", volume, { volume = it }, "ml") }
                NumberRow("Strength", abv, { abv = it }, "% ABV")
            }
            MoneyField("Price", price, { price = it }, currency)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onDelete) { Text("Delete", color = MaterialTheme.colorScheme.error) }
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = onDismiss) { Text("Cancel") }
                Button(
                    onClick = {
                        val override = if (isUnits || abv == entry.drink.abv) null else abv
                        onDone(Instant.ofEpochMilli(time), vessel, volume, price, override)
                    },
                    enabled = valid,
                ) { Text("Done") }
            }
            Spacer(Modifier.size(8.dp))
        }
    }

    if (pickingTime) {
        val shown = Instant.ofEpochMilli(time).atZone(clock.zone)
        val picker = rememberTimePickerState(shown.hour, shown.minute, DateFormat.is24HourFormat(context))
        AlertDialog(
            onDismissRequest = { pickingTime = false },
            confirmButton = {
                TextButton(onClick = {
                    time = resolveTime(clock, day, picker.hour, picker.minute).toEpochMilli()
                    pickingTime = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { pickingTime = false }) { Text("Cancel") } },
            text = { TimePicker(picker) },
        )
    }
}

/** A clock time placed within the drinking day, so 01:30 lands after midnight rather than before the day began. */
internal fun resolveTime(clock: DayClock, day: DayKey, hour: Int, minute: Int): Instant =
    clock.resolve(LocalDateTime.of(day.localDate, LocalTime.of(hour, minute)).atZone(clock.zone).toInstant(), day)

/** A day's spend set in one go, for a night when the total is known but not each round. Cleared, it falls back to what the drinks add up to. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SpendSheet(derived: Double, override: Double?, currency: String, onSave: (Double?) -> Unit, onDismiss: () -> Unit) {
    var amount by rememberSaveable { mutableDoubleStateOf(override ?: derived) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.padding(horizontal = 24.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Spent", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            MoneyField("Spent", amount, { amount = it }, currency)
            Text(
                "Stands in for what the drinks add up to. Units and calories are unaffected.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (override != null) {
                TextButton(onClick = { onSave(null) }) { Text("Back to drink prices", color = MaterialTheme.colorScheme.error) }
                Text(
                    "The drinks logged come to ${derived.money(currency)}.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                OutlinedButton(onClick = onDismiss) { Text("Cancel") }
                Button(onClick = { onSave(amount) }) { Text("Save") }
            }
        }
    }
}
