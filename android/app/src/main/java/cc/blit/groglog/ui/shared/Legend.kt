package cc.blit.groglog.ui.shared

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** A chart's keys, wrapping onto further rows when the text is large rather than running off the card. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LegendRow(modifier: Modifier = Modifier, spacing: Dp = 16.dp, content: @Composable () -> Unit) {
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(spacing), verticalArrangement = Arrangement.spacedBy(6.dp)) { content() }
}

/**
 * A series swatch for a chart's key: a filled block for a series drawn as bars, a line otherwise. Where bars are
 * coloured by how far over budget they are, `ramp` carries the whole scale.
 */
@Composable
fun LegendKey(label: String, color: Color, dashed: Boolean = false, bar: Boolean = false, ramp: List<Color> = emptyList()) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        val density = LocalDensity.current
        if (bar) {
            Canvas(Modifier.size(9.dp, 12.dp)) {
                val brush = if (ramp.isEmpty()) Brush.linearGradient(listOf(color, color)) else Brush.verticalGradient(ramp.reversed())
                drawRoundRect(brush, cornerRadius = CornerRadius(2.dp.toPx()))
            }
        } else {
            Canvas(Modifier.size(18.dp, 4.dp)) {
                drawLine(
                    color,
                    Offset(1.5.dp.toPx(), size.height / 2),
                    Offset(size.width - 1.5.dp.toPx(), size.height / 2),
                    strokeWidth = with(density) { 3.dp.toPx() },
                    cap = StrokeCap.Round,
                    pathEffect = if (dashed) PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 4.dp.toPx() + 3.dp.toPx())) else null,
                )
            }
        }
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
