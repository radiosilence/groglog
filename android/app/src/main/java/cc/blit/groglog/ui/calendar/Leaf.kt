package cc.blit.groglog.ui.calendar

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/** The mark for an alcohol-free day, as iOS's `leaf.fill`. Material's core icons have no leaf. */
val Leaf: ImageVector = ImageVector.Builder("Leaf", 24.dp, 24.dp, 24f, 24f).apply {
    path(fill = SolidColor(Color.Black)) {
        moveTo(5.5f, 18.5f)
        curveTo(4.5f, 10.5f, 10f, 4.5f, 20.5f, 3.5f)
        curveTo(20.5f, 13.5f, 15f, 19.5f, 6.5f, 19f)
        close()
        moveTo(3.3f, 20.6f)
        lineTo(12.6f, 11.3f)
        lineTo(13.4f, 12.1f)
        lineTo(4.1f, 21.4f)
        close()
    }
}.build()
