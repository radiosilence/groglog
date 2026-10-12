package cc.blit.groglog.ui.shared

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * Hand-drawn drink icon. Drawn on a 100×100 canvas so every vessel shares one coordinate space. `fill` is how far
 * poured, 0…1; animate it when a drink is logged. Decorative: the label beside it carries the meaning for TalkBack.
 */
@Composable
fun DrinkGlyph(
    category: DrinkCategory,
    vessel: Vessel,
    modifier: Modifier = Modifier,
    volumeMl: Double? = null,
    fill: Float = 1f,
) {
    if (category == DrinkCategory.UNITS) {
        UnitsBadge(modifier)
        return
    }
    val art = remember(vessel, volumeMl) { Art(vessel, volumeMl ?: vessel.volumes[0]) }
    val ink = LocalContentColor.current
    Canvas(modifier.aspectRatio(1f)) {
        val scale = min(size.width, size.height) / 100f
        translate((size.width - 100 * scale) / 2, (size.height - 100 * scale) / 2) {
            scale(scale, pivot = Offset.Zero) {
                art.draw(this, category, fill, ink)
            }
        }
    }
}

/** A bare unit count has no vessel, so it gets a counter instead. */
@Composable
private fun UnitsBadge(modifier: Modifier) {
    BoxWithConstraints(modifier.aspectRatio(1f), contentAlignment = Alignment.Center) {
        val side = min(maxWidth.value, maxHeight.value)
        val textSize = with(LocalDensity.current) { (side * 0.5f).dp.toSp() }
        Box(
            Modifier
                .size((side * 0.72f).dp)
                .background(GrogColors.grog, CircleShape)
                .border((side * 0.035f).dp, LocalContentColor.current, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text("u", color = Color.White, fontSize = textSize, fontWeight = FontWeight.Black)
        }
    }
}

private fun rect(x: Float, y: Float, width: Float, height: Float) = Rect(x, y, x + width, y + height)

private fun pathOf(build: Path.() -> Unit) = Path().apply(build)

private fun rectPath(rect: Rect) = pathOf { addRect(rect) }

private fun roundedPath(rect: Rect, radius: Float) = pathOf { addRoundRect(RoundRect(rect, CornerRadius(radius))) }

private fun ovalPath(rect: Rect) = pathOf { addOval(rect) }

private fun Path.op(other: Path, operation: PathOperation) = Path().also { it.op(this, other, operation) }

private infix fun Path.intersect(other: Path) = op(other, PathOperation.Intersect)

private infix fun Path.union(other: Path) = op(other, PathOperation.Union)

private fun Path.transformed(matrix: Matrix) = Path().also {
    it.addPath(this)
    it.transform(matrix)
}

internal class Art(val vessel: Vessel, volumeMl: Double) {
    /** Outline of the vessel; tinted as glass and stroked. */
    var glass: Path

    /** Where liquid can sit, if different from the glass (above a thick base, say). */
    var bowl: Path? = null

    /** Fraction of the bowl's height that is filled. */
    val level: Float

    /** Stems, feet, caps: filled with ink. */
    var solids: List<Path> = emptyList()

    /** Labels on bottles and cans, drawn over the liquid. */
    var label: Path? = null
    var labelMark: Path? = null
    var ice = false
    var garnish = false

    init {
        when (vessel) {
            Vessel.PINT -> {
                glass = nonic(6f)
                level = 0.86f
            }
            Vessel.HALF -> {
                glass = nonic(36f)
                level = 0.8f
            }
            Vessel.CAN -> {
                glass = roundedPath(rect(30f, 12f, 40f, 84f), 7f)
                level = 1f
                solids = listOf(roundedPath(rect(43f, 7f, 14f, 4f), 2f))
                label = rectPath(rect(30f, 42f, 40f, 30f))
                labelMark = star(Offset(50f, 57f), 11f)
            }
            Vessel.BOTTLE -> {
                glass = bottle(44f, 56f, 35f, 65f, neckTop = 10f, shoulder = 30f, bodyTop = 52f)
                level = 0.92f
                solids = listOf(roundedPath(rect(42.5f, 5f, 15f, 6f), 2f))
                label = rectPath(rect(35f, 60f, 30f, 22f))
                labelMark = ovalPath(rect(44f, 65f, 12f, 12f))
            }
            Vessel.WINE_BOTTLE -> {
                glass = bottle(45f, 55f, 33f, 67f, neckTop = 6f, shoulder = 28f, bodyTop = 46f)
                level = 0.9f
                solids = listOf(roundedPath(rect(44f, 3f, 12f, 16f), 2f))
                label = rectPath(rect(33f, 60f, 34f, 24f))
                labelMark = ovalPath(rect(44f, 66f, 12f, 12f))
            }
            Vessel.WINE_GLASS -> {
                glass = pathOf {
                    moveTo(27f, 8f)
                    lineTo(73f, 8f)
                    cubicTo(76f, 32f, 71f, 51f, 50f, 56f)
                    cubicTo(29f, 51f, 24f, 32f, 27f, 8f)
                    close()
                }
                level = when {
                    volumeMl <= 70 -> 0.3f
                    volumeMl <= 125 -> 0.45f
                    volumeMl <= 175 -> 0.58f
                    else -> 0.74f
                }
                solids = stem(55f, 3.6f) + ovalPath(rect(30f, 88f, 40f, 8f))
            }
            Vessel.FLUTE -> {
                glass = pathOf {
                    moveTo(39f, 6f)
                    lineTo(61f, 6f)
                    cubicTo(62f, 34f, 60f, 54f, 50f, 62f)
                    cubicTo(40f, 54f, 38f, 34f, 39f, 6f)
                    close()
                }
                level = 0.82f
                solids = stem(61f, 3f) + ovalPath(rect(35f, 88f, 30f, 7f))
            }
            Vessel.SHOT -> {
                glass = tapered(46f, 34f, 66f, 4f)
                bowl = tapered(46f, 34f, 66f, 4f, bottom = 84f)
                level = 0.72f
            }
            Vessel.TUMBLER -> {
                glass = tapered(36f, 26f, 74f, 3f)
                bowl = tapered(36f, 26f, 74f, 3f, bottom = 89f)
                level = 0.55f
                ice = true
            }
            Vessel.COUPE -> {
                glass = pathOf {
                    moveTo(20f, 14f)
                    lineTo(80f, 14f)
                    lineTo(52f, 46f)
                    quadraticTo(50f, 48.5f, 48f, 46f)
                    close()
                }
                level = 0.8f
                solids = stem(46f, 3f) + ovalPath(rect(33f, 88f, 34f, 7f))
                garnish = true
            }
        }
        sizing[vessel]?.let { (full, exponent) -> scale((volumeMl / full).pow(exponent)) }
    }

    /**
     * Rectangular containers are drawn to size: the largest common serve fills the frame and smaller ones shrink
     * towards its base, so a 330 can sits visibly shorter than a 568.
     */
    private fun scale(by: Double) {
        val factor = by.coerceIn(0.5, 1.0)
        val matrix = Matrix().apply {
            translate(50f, 96f)
            scale(factor.pow(0.35).toFloat(), factor.toFloat())
            translate(-50f, -96f)
        }
        glass = glass.transformed(matrix)
        bowl = bowl?.transformed(matrix)
        solids = solids.map { it.transformed(matrix) }
        label = label?.transformed(matrix)
        labelMark = labelMark?.transformed(matrix)
    }

    fun draw(scope: DrawScope, category: DrinkCategory, fill: Float, ink: Color) = with(scope) {
        val liquidColor = Color(category.liquid)
        val liquidArea = bowl ?: glass
        val bounds = liquidArea.getBounds()
        val full = bounds.bottom - bounds.height * level
        val surface = bounds.bottom - bounds.height * level * fill.coerceIn(0f, 1f)
        val hasHead = category.hasHead && (vessel == Vessel.PINT || vessel == Vessel.HALF)

        drawPath(glass, ink.copy(alpha = 0.06f))

        clipPath(liquidArea) {
            drawRect(liquidColor, Offset(0f, surface), androidx.compose.ui.geometry.Size(100f, 100f))
            if (category.isFizzy && label == null) {
                for ((x, y, r) in bubbles) {
                    val centre = Offset(bounds.left + bounds.width * x, surface + (bounds.bottom - surface) * y)
                    drawCircle(Color.White.copy(alpha = 0.7f), r, centre)
                }
            }
        }

        var foam: Path? = null
        if (hasHead && fill > 0.05f) {
            // The head rides on the liquid as it pours, and crowns over the rim once full.
            val top = surface - (full - bounds.top)
            val head = rectPath(rect(0f, top, 100f, surface - top + 1)) intersect glass
            val heads = Path()
            val count = max(2, ((bounds.width - 10) / 8.5f).toInt() + 1)
            for (index in 0 until count) {
                val x = bounds.left + 5 + (bounds.width - 10) * index / (count - 1)
                heads.addOval(rect(x - 5.5f, top - 4.5f, 11f, 10f))
            }
            foam = (head union if (fill >= 1f) heads else heads intersect glass).also { drawPath(it, Color.White) }
        }

        val bowl = bowl
        if (ice && bowl != null) {
            val iceBounds = bowl.getBounds()
            for ((dx, dy, angle) in cubes) {
                val cube = rect(iceBounds.left + iceBounds.width * dx, surface - 6 + iceBounds.height * dy * 0.4f, 15f, 15f)
                rotate(angle, cube.center) {
                    val shape = roundedPath(cube, 3f)
                    drawPath(shape, Color.White.copy(alpha = 0.55f))
                    drawPath(shape, ink.copy(alpha = 0.5f), style = Stroke(1.8f))
                }
            }
        }

        label?.let { label ->
            drawPath(label intersect glass, Color.White.copy(alpha = 0.92f))
            labelMark?.let { drawPath(it, if (vessel == Vessel.CAN) Color.Red else liquidColor) }
        }

        val line = Stroke(3.5f, cap = StrokeCap.Round, join = StrokeJoin.Round)
        drawPath(glass, ink, style = line)
        foam?.let { drawPath(it, ink, style = Stroke(2.5f, join = StrokeJoin.Round)) }
        for (solid in solids) drawPath(solid, ink)

        if (garnish) {
            drawLine(ink, Offset(66f, 8f), Offset(56f, 26f), 3.5f, StrokeCap.Round)
            drawOval(Color(0.8f, 0.1f, 0.2f), Offset(60f, 6f), androidx.compose.ui.geometry.Size(11f, 11f))
        }

        if (label == null && vessel != Vessel.CAN) {
            clipPath(glass) {
                drawLine(
                    Color.White.copy(alpha = 0.6f),
                    Offset(bounds.left + bounds.width * 0.2f, bounds.top + bounds.height * 0.18f),
                    Offset(bounds.left + bounds.width * 0.22f, bounds.top + bounds.height * 0.5f),
                    3f,
                    StrokeCap.Round,
                )
            }
        }
    }

    private companion object {
        val bubbles = listOf(
            Triple(0.3f, 0.55f, 1.6f),
            Triple(0.62f, 0.7f, 2.0f),
            Triple(0.45f, 0.85f, 1.4f),
            Triple(0.7f, 0.42f, 1.3f),
            Triple(0.38f, 0.3f, 1.1f),
        )

        val cubes = listOf(Triple(0.2f, 0.2f, -12f), Triple(0.5f, 0.26f, 10f))

        val sizing = mapOf(
            Vessel.CAN to (568.0 to 0.6),
            Vessel.BOTTLE to (660.0 to 0.5),
            Vessel.WINE_BOTTLE to (750.0 to 0.4),
        )

        /** A nonic pint glass with its characteristic bulge near the rim. */
        fun nonic(top: Float): Path {
            val bulge = top + (96 - top) * 0.27f
            return pathOf {
                moveTo(24f, top)
                lineTo(76f, top)
                lineTo(73f, bulge - 4)
                quadraticTo(76f, bulge, 73f, bulge + 4)
                lineTo(67f, 93f)
                quadraticTo(66.5f, 96f, 63f, 96f)
                lineTo(37f, 96f)
                quadraticTo(33.5f, 96f, 33f, 93f)
                lineTo(27f, bulge + 4)
                quadraticTo(24f, bulge, 27f, bulge - 4)
                close()
            }
        }

        fun bottle(neckLeft: Float, neckRight: Float, bodyLeft: Float, bodyRight: Float, neckTop: Float, shoulder: Float, bodyTop: Float): Path {
            val mid = (shoulder + bodyTop) / 2
            return pathOf {
                moveTo(neckLeft, neckTop)
                lineTo(neckRight, neckTop)
                lineTo(neckRight, shoulder)
                cubicTo(neckRight, mid, bodyRight, mid, bodyRight, bodyTop)
                lineTo(bodyRight, 92f)
                quadraticTo(bodyRight, 96f, bodyRight - 4, 96f)
                lineTo(bodyLeft + 4, 96f)
                quadraticTo(bodyLeft, 96f, bodyLeft, 92f)
                lineTo(bodyLeft, bodyTop)
                cubicTo(bodyLeft, mid, neckLeft, mid, neckLeft, shoulder)
                close()
            }
        }

        /** Straight-sided glass narrowing towards the base. */
        fun tapered(top: Float, left: Float, right: Float, inset: Float, bottom: Float = 96f): Path {
            val t = (bottom - top) / (96 - top)
            return pathOf {
                moveTo(left, top)
                lineTo(right, top)
                lineTo(right - inset * t, bottom)
                lineTo(left + inset * t, bottom)
                close()
            }
        }

        fun stem(top: Float, width: Float) = listOf(rectPath(rect(50 - width / 2, top, width, 90 - top)))

        fun star(center: Offset, radius: Float) = pathOf {
            for (i in 0 until 10) {
                val r = if (i % 2 == 0) radius else radius * 0.45f
                val angle = i * PI / 5 - PI / 2
                val x = center.x + cos(angle).toFloat() * r
                val y = center.y + sin(angle).toFloat() * r
                if (i == 0) moveTo(x, y) else lineTo(x, y)
            }
            close()
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun DrinkGlyphPreview() {
    GrogLogTheme {
        Surface {
            FlowRow(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (vessel in Vessel.entries) DrinkGlyph(DrinkCategory.BEER, vessel, Modifier.size(64.dp))
                DrinkGlyph(DrinkCategory.RED_WINE, Vessel.WINE_GLASS, Modifier.size(64.dp), 250.0)
                DrinkGlyph(DrinkCategory.STOUT, Vessel.PINT, Modifier.size(64.dp), fill = 0.5f)
                DrinkGlyph(DrinkCategory.UNITS, Vessel.SHOT, Modifier.size(64.dp))
            }
        }
    }
}

@Preview(showBackground = true, backgroundColor = 0xFF000000, uiMode = android.content.res.Configuration.UI_MODE_NIGHT_YES)
@Composable
private fun DrinkGlyphDarkPreview() {
    GrogLogTheme(darkTheme = true) {
        Surface {
            Box(Modifier.size(96.dp).padding(8.dp)) {
                DrinkGlyph(DrinkCategory.CIDER, Vessel.PINT, Modifier.fillMaxSize())
            }
        }
    }
}
