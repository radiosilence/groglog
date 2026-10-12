package cc.blit.groglog.widget

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.core.graphics.createBitmap
import cc.blit.groglog.model.CurvePoint
import cc.blit.groglog.model.Serve
import cc.blit.groglog.ui.shared.Art

/**
 * What RemoteViews cannot draw, drawn into bitmaps: the burndown chart, the draining ring and the drink glyphs. Colours are fixed rather
 * than themed because a bitmap is not re-resolved for night mode; the heat colours are the same in both.
 */
internal object Drawings {
    /**
     * The budget draining through the day, or the units climbing with no goal, as a step chart over the 24 hours of
     * the day: a line in `color` over an area of it at 22%.
     */
    fun burndown(points: List<CurvePoint>, color: Int, width: Int, height: Int, density: Float): Bitmap {
        val bitmap = createBitmap(width.coerceAtLeast(1), height.coerceAtLeast(1))
        if (points.isEmpty()) return bitmap
        val stroke = 1.5f * density
        val top = stroke / 2
        val bottom = height - stroke / 2
        val peak = points.maxOf { it.units }.takeIf { it > 0 } ?: 1.0
        fun x(hours: Double) = (hours.coerceIn(0.0, 24.0) / 24 * width).toFloat()
        fun y(units: Double) = (bottom - units / peak * (bottom - top)).toFloat()

        val line = Path().apply {
            moveTo(x(points[0].x), y(points[0].units))
            for (index in 1 until points.size) {
                lineTo(x(points[index].x), y(points[index - 1].units))
                lineTo(x(points[index].x), y(points[index].units))
            }
        }
        val area = Path(line).apply {
            lineTo(x(points.last().x), height.toFloat())
            lineTo(x(points[0].x), height.toFloat())
            close()
        }
        val canvas = Canvas(bitmap)
        canvas.drawPath(area, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; alpha = 56 })
        canvas.drawPath(line, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        })
        return bitmap
    }

    /**
     * The day's budget as a ring that drains as drinks are logged, from twelve o'clock clockwise, over a faint track.
     */
    fun ring(left: Float, color: Int, size: Int, density: Float): Bitmap {
        val bitmap = createBitmap(size.coerceAtLeast(1), size.coerceAtLeast(1))
        val stroke = 4f * density
        val inset = stroke / 2 + density
        val bounds = RectF(inset, inset, size - inset, size - inset)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
        }
        val canvas = Canvas(bitmap)
        canvas.drawOval(bounds, paint.apply { this.color = color; alpha = 64 })
        if (left > 0) canvas.drawArc(bounds, -90f, 360f * left, false, paint.apply { this.color = color; alpha = 255 })
        return bitmap
    }

    /**
     * A tile's drink in its vessel, as the Log grid draws it. The outline is a warm grey rather than the theme's text
     * colour, which a bitmap could not follow from light to dark.
     */
    fun glyph(serve: Serve, size: Int): Bitmap {
        val bitmap = createBitmap(size.coerceAtLeast(1), size.coerceAtLeast(1))
        val art = Art(serve.vessel, serve.volumeMl)
        val side = size.toFloat()
        CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, androidx.compose.ui.graphics.Canvas(Canvas(bitmap)), Size(side, side)) {
            scale(side / 100f, pivot = Offset.Zero) { art.draw(this, serve.drink.category, 1f, glyphInk) }
        }
        return bitmap
    }

    private val glyphInk = Color(0xFF8C8279)
}
