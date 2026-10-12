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
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * "Log a drink" in Quick Settings, the nearest Android has to the iPhone's Action Button: a tap logs the first tile on
 * the Log grid, the drink most recently drunk. A long press opens the app (the `QS_TILE_PREFERENCES` alias in the
 * manifest). The tile stays as it is, an action rather than a switch, and its subtitle says where the day stands once
 * the drink is logged.
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
        }
    }

    private fun show(serve: Serve?, outcome: Outcome?) {
        val logged = outcome as? Logged
        val tile = qsTile ?: return
        tile.state = if (serve == null) Tile.STATE_UNAVAILABLE else Tile.STATE_INACTIVE
        val detail = when {
            logged != null -> "Logged · ${logged.units.unitsText} today"
            outcome == Failed -> "Couldn't log"
            serve != null -> "${serve.drink.name}, ${serve.vessel.shortLabel(serve.volumeMl).lowercase()}"
            else -> "No drinks on the Log grid"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.label = "Log a drink"
            tile.subtitle = detail
        } else {
            tile.label = detail
        }
        tile.contentDescription = logged?.let { "Logged ${it.serve.drink.name}. ${it.summary}" } ?: "Log a drink: $detail"
        tile.updateTile()
    }
}
