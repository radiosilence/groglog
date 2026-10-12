package cc.blit.groglog.ui.shared

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/**
 * The top of every sheet, as iOS lays out a sheet's toolbar: Cancel on the left, the title, the primary action on the
 * right. A sheet with nothing to cancel, such as a picker that logs as it goes, passes no `onCancel`.
 */
@Composable
fun SheetBar(
    title: String,
    action: String,
    onAction: () -> Unit,
    modifier: Modifier = Modifier,
    onCancel: (() -> Unit)? = null,
    enabled: Boolean = true,
) {
    Row(modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        // Both ends take the same room, so the title stays centred whatever the buttons say.
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (onCancel != null) TextButton(onClick = onCancel) { Text("Cancel", maxLines = 1) }
        }
        Text(
            title,
            Modifier.weight(2f).semantics { heading() },
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            Button(onClick = onAction, enabled = enabled, modifier = Modifier.widthIn(min = 64.dp)) { Text(action, maxLines = 1) }
        }
    }
}
