package cc.blit.groglog.ui.log

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.ui.shared.TimeRow
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.time.Instant

/** Logs a bare number of units, for when the total is known but not the drinks. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UnitsSheet(day: DayKey, clock: DayClock, initialTime: Instant, onDismiss: () -> Unit, onLog: (units: Double, time: Instant) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        UnitsForm(day, clock, initialTime, onDismiss, onLog)
    }
}

@Composable
private fun UnitsForm(day: DayKey, clock: DayClock, initialTime: Instant, onDismiss: () -> Unit, onLog: (Double, Instant) -> Unit) {
    var text by rememberSaveable { mutableStateOf("") }
    var time by remember { mutableStateOf(initialTime) }
    val units = text.replace(',', '.').toDoubleOrNull()?.takeIf { it > 0 }
    val focus = remember { FocusRequester() }
    LaunchedEffect(focus) { focus.requestFocus() }

    fun log() {
        units ?: return
        onLog(units, time)
        onDismiss()
    }

    Column(Modifier.imePadding().padding(bottom = 16.dp)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDismiss) { Text("Cancel") }
            Text("Units", Modifier.weight(1f).semantics { heading() }, style = MaterialTheme.typography.titleMedium, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Button(onClick = ::log, enabled = units != null) { Text("Log") }
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val figure = MaterialTheme.typography.displayMedium.copy(fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
            BasicTextField(
                value = text,
                onValueChange = { new -> text = new.filter { it.isDigit() || it == '.' || it == ',' }.take(6) },
                modifier = Modifier.weight(1f).focusRequester(focus).semantics { contentDescription = "Units" },
                textStyle = figure,
                singleLine = true,
                cursorBrush = SolidColor(GrogColors.grog),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { log() }),
                decorationBox = { field ->
                    if (text.isEmpty()) Text("0", style = figure.copy(color = MaterialTheme.colorScheme.outline))
                    field()
                },
            )
            Text("units", Modifier.padding(bottom = 8.dp), style = MaterialTheme.typography.titleLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        TimeRow("At", time, { time = it }, clock, day)
        Text(
            "Counts towards the day like any drink. Use it for totals from another app, or a night you did not log drink by drink.",
            Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun UnitsFormPreview() {
    val clock = DayClock(5)
    GrogLogTheme { Surface { UnitsForm(clock.today, clock, Instant.now(), {}, { _, _ -> }) } }
}
