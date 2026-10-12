package cc.blit.groglog.ui.day

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.money
import cc.blit.groglog.ui.shared.MoneyField

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
