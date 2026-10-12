package cc.blit.groglog.shortcut

import android.content.Context
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import cc.blit.groglog.R
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Serves
import cc.blit.groglog.model.unitsText

/**
 * The launcher's long-press menu: the most recently drunk tiles, each logging without opening the app, beside the
 * static "Log units" shortcut (`res/xml/shortcuts.xml`).
 */
object Shortcuts {
    /** Launchers show four shortcuts in all, and one is "Log units". */
    private const val DRINKS = 3

    /**
     * Publishes the most recent tiles, or nothing when they have not changed: updates from the background are
     * rate-limited, and logging a drink commits far more often than it changes which drinks are recent.
     *
     * The menu keeps its order while its drinks stay the same. The grid reorders on every log, and following it would
     * move the shortcut just used out from under the finger; a drink new to the menu goes after those already in it.
     */
    suspend fun publish(context: Context, database: AppDatabase) {
        val recent = Serves.grid(database).take(DRINKS)
        val published = ShortcutManagerCompat.getDynamicShortcuts(context).sortedBy { it.rank }.map { it.id }
        val ordered = recent.sortedBy { serve -> published.indexOf(serve.id).takeIf { it >= 0 } ?: (DRINKS + recent.indexOf(serve)) }
        val shortcuts = ordered.mapIndexed { rank, serve ->
            val size = serve.vessel.label(serve.volumeMl)
            ShortcutInfoCompat.Builder(context, serve.id)
                .setShortLabel(serve.drink.name)
                .setLongLabel("${serve.drink.name}, ${size.replaceFirstChar { it.lowercase() }} (${serve.units.unitsText} u)")
                .setIcon(IconCompat.createWithResource(context, R.drawable.ic_shortcut_drink))
                .setIntent(LogShortcutActivity.intent(context, serve.id))
                .setRank(rank)
                .build()
        }
        val current = ShortcutManagerCompat.getDynamicShortcuts(context).sortedBy { it.rank }
        val unchanged = current.size == shortcuts.size && current.zip(shortcuts).all { (a, b) ->
            a.id == b.id && a.shortLabel == b.shortLabel && a.longLabel == b.longLabel && a.rank == b.rank
        }
        if (!unchanged) ShortcutManagerCompat.setDynamicShortcuts(context, shortcuts)
    }
}
