package cc.blit.groglog.ui.shared

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/** Material Symbols the core icon set lacks, from their 24 dp path data. */
object GrogIcons {
    val Undo: ImageVector by lazy {
        icon("Undo", "M12.5,8c-2.65,0 -5.05,0.99 -6.9,2.6L2,7v9h9l-3.62,-3.62c1.39,-1.16 3.16,-1.88 5.12,-1.88 3.54,0 6.55,2.31 7.6,5.5l2.37,-0.78C21.08,11.03 17.15,8 12.5,8z")
    }

    /** The alcohol-free mark, as the leaf is on iOS. */
    val Leaf: ImageVector by lazy {
        icon("Leaf", "M6.05,8.05c-2.73,2.73 -2.73,7.15 -0.02,9.88c1.47,-3.4 4.09,-6.24 7.36,-7.93c-2.77,2.34 -4.71,5.61 -5.39,9.32c2.6,1.23 5.8,0.78 7.95,-1.37C19.43,14.47 20,4 20,4S9.53,4.57 6.05,8.05z")
    }

    val Remove: ImageVector by lazy { icon("Remove", "M19,13H5v-2h14v2z") }

    private fun icon(name: String, path: String) =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
            .addPath(addPathNodes(path), fill = SolidColor(Color.Black))
            .build()
}
