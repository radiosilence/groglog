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
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.money
import cc.blit.groglog.ui.shared.MoneyField
import cc.blit.groglog.ui.shared.moneyDigits
import cc.blit.groglog.ui.shared.moneyValue
import cc.blit.groglog.ui.shared.SheetBar
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding

/** A day's spend set in one go, for a night when the total is known but not each round. Cleared, it falls back to what the drinks add up to. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SpendSheet(derived: Double, override: Double?, currency: String, onSave: (Double?) -> Unit, onDismiss: () -> Unit) {
    val amount = rememberTextFieldState(moneyDigits(override ?: derived, currency))
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        SheetBar(title = "Spent", action = "Save", onAction = { onSave(moneyValue(amount.text, currency)) }, onCancel = onDismiss)
        Column(Modifier.padding(horizontal = 8.dp).navigationBarsPadding().imePadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            MoneyField("Spent", amount, currency)
            Text(
                "Stands in for what the drinks add up to. Units and calories are unaffected.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
            if (override != null) {
                TextButton(onClick = { onSave(null) }) { Text("Back to drink prices", color = MaterialTheme.colorScheme.error) }
                Text(
                    "The drinks logged come to ${derived.money(currency)}.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}
