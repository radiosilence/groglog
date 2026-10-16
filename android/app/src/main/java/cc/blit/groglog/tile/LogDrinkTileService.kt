package cc.blit.groglog.tile

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import cc.blit.groglog.container
import cc.blit.groglog.data.Serves
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.widget.Failed
import cc.blit.groglog.widget.Logged
import cc.blit.groglog.widget.Outcome
import cc.blit.groglog.widget.QuickLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * "Log a drink" in Quick Settings, the nearest Android has to the iPhone's Action Button: a tap logs the first tile on
 * the Log grid, the drink most recently drunk. A long press opens the app (the `QS_TILE_PREFERENCES` alias in the
 * manifest). Once the drink is logged the tile says so in its label and lights for two seconds, then goes back to an
 * action ready for the next tap; its subtitle says where the day stands.
 */
class LogDrinkTileService : TileService() {
    override fun onStartListening() {
        val container = applicationContext.container
        container.scope.launch {
            val serve = Serves.grid(container.liveDatabase).firstOrNull()
            withContext(Dispatchers.Main) { show(serve, null) }
        }
    }

    override fun onClick() {
        val container = applicationContext.container
        // The process-wide scope, so the write finishes even if the shade closes and the service is unbound.
        container.scope.launch {
            val serve = Serves.grid(container.liveDatabase).firstOrNull() ?: return@launch
            val logged = QuickLog.log(serve.id, container.liveDatabase, container.livePrefs.current())
            withContext(Dispatchers.Main) { show(serve, logged) }
            // The result in the tile's own label and state for a moment, so the small tile shows it too, then back to
            // an action ready for the next tap.
            delay(2_000)
            withContext(Dispatchers.Main) { show(serve, null) }
        }
    }

    private fun show(serve: Serve?, outcome: Outcome?) {
        val logged = outcome as? Logged
        val tile = qsTile ?: return
        tile.state = when {
            serve == null -> Tile.STATE_UNAVAILABLE
            logged != null -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        val detail = when {
            logged != null -> "Logged · ${logged.units.unitsText} today"
            outcome == Failed -> "Couldn't log"
            serve != null -> "${serve.drink.name}, ${serve.vessel.shortLabel(serve.volumeMl).lowercase()}"
            else -> "No drinks on the Log grid"
        }
        val label = when {
            logged != null -> "Logged"
            outcome == Failed -> "Couldn't log"
            else -> "Log a drink"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.label = label
            tile.subtitle = detail
        } else {
            tile.label = if (outcome == null) detail else label
        }
        tile.contentDescription = logged?.let { "Logged ${it.serve.drink.name}. ${it.summary}" } ?: "Log a drink: $detail"
        tile.updateTile()
    }
}
