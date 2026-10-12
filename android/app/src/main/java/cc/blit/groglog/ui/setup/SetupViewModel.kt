package cc.blit.groglog.ui.setup

import android.content.ContentResolver
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.export.Exporter
import cc.blit.groglog.export.ImportException
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.ui.LedgerState
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Something to tell the user after an action finishes: a dialog when it needs reading, otherwise a brief message. */
sealed interface Notice {
    data class Dialog(val title: String, val text: String) : Notice
    data class Brief(val text: String) : Notice
}

/**
 * Setup's settings and data. `background` is the application's scope, for work that must finish even if the screen
 * goes, such as reassigning every entry after the day-end hour changes.
 */
class SetupViewModel(
    private val database: AppDatabase,
    private val prefs: Prefs,
    private val background: CoroutineScope,
    private val exports: File,
) : ViewModel() {
    /** Null until the first read lands. */
    val state: StateFlow<LedgerState?> = combine(prefs.settings, database.queries().days()) { settings, days -> LedgerState(settings, Ledger(days, settings.clock)) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val dynamicColour: StateFlow<Boolean> = prefs.dynamicColour.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    private val _notice = MutableStateFlow<Notice?>(null)
    val notice: StateFlow<Notice?> = _notice.asStateFlow()

    fun dismissNotice() {
        _notice.value = null
    }

    /** Moves the day's end and reassigns every entry to a day under the new hour: seconds on a long log. */
    fun setRolloverHour(hour: Int): Job = background.launch {
        if (prefs.current().rolloverHour == hour) return@launch
        prefs.moveDayEnd(hour, database)
    }

    fun setCurrency(code: String) {
        viewModelScope.launch { prefs.setCurrency(code) }
    }

    fun setDynamicColour(on: Boolean) {
        viewModelScope.launch { prefs.setDynamicColour(on) }
    }

    fun resetPrices(): Job = viewModelScope.launch {
        val changed = Logbook(database, prefs.current().clock).resetPrices()
        _notice.value = Notice.Dialog(
            "Prices reset",
            if (changed == 0) "Everything already matched the catalogue." else "${count(changed, "price")} changed.",
        )
    }

    fun rebuild() {
        background.launch { Logbook(database, prefs.current().clock).rebuild() }
    }

    suspend fun export(kind: Exporter.Kind): ByteArray = withContext(Dispatchers.IO) {
        val backup = Exporter.backup(database, prefs.current())
        when (kind) {
            Exporter.Kind.JSON -> Exporter.json(backup)
            Exporter.Kind.MARKDOWN -> Exporter.markdown(backup).toByteArray()
        }
    }

    suspend fun fileName(kind: Exporter.Kind): String = Exporter.fileName(kind, prefs.current())

    /** Writes an export where the share sheet can reach it, replacing any earlier one. */
    suspend fun exportFile(kind: Exporter.Kind): File {
        val bytes = export(kind)
        val name = fileName(kind)
        return withContext(Dispatchers.IO) {
            exports.mkdirs()
            exports.listFiles()?.forEach { it.delete() }
            File(exports, name).apply { writeBytes(bytes) }
        }
    }

    fun saveBackup(uri: Uri, resolver: ContentResolver): Job = viewModelScope.launch {
        val bytes = export(Exporter.Kind.JSON)
        _notice.value = try {
            withContext(Dispatchers.IO) {
                resolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } ?: throw IOException("No stream")
            }
            Notice.Brief("Backup saved.")
        } catch (error: IOException) {
            Notice.Dialog("Backup not saved", "The file could not be written.")
        }
    }

    /** In the application's scope, so leaving Setup partway through cannot cancel a merge halfway. */
    fun import(uri: Uri, resolver: ContentResolver): Job = background.launch {
        _notice.value = import { resolver.openInputStream(uri) ?: throw IOException("No stream") }
    }

    /** Reads and merges a backup, and says what happened in words fit to show. */
    internal suspend fun import(open: () -> InputStream): Notice =
        try {
            val bytes = withContext(Dispatchers.IO) { open().use { readBackup(it) } }
            val added = Exporter.restore(bytes, database, prefs)
            Notice.Dialog("Backup imported", "Imported ${count(added, "drink")}.")
        } catch (error: CancellationException) {
            throw error
        } catch (error: ImportException) {
            failed(error.message ?: "")
        } catch (error: IOException) {
            failed("The file could not be read.")
        } catch (error: Exception) {
            // Anything else the file can do to the decoder or the merge, such as a value of the wrong type or an entry
            // listed twice under one id: nothing has been written, and the reason is given for anyone who asks.
            failed("The file is not a GrogLog backup, or it is damaged.${error.message?.let { "\n\n$it" } ?: ""}")
        }

    private fun failed(reason: String) = Notice.Dialog("Import failed", reason)

    companion object {
        /** Ten years of heavy logging is a few megabytes; a file near this is not a backup. */
        const val MAX_IMPORT_BYTES = 50_000_000

        /** Reads at most `limit` bytes, refusing anything larger without reading it all. */
        internal fun readBackup(stream: InputStream, limit: Int = MAX_IMPORT_BYTES): ByteArray {
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = stream.read(buffer)
                if (read < 0) return out.toByteArray()
                out.write(buffer, 0, read)
                if (out.size() > limit) throw ImportException.tooLarge()
            }
        }

        internal fun count(n: Int, noun: String) = if (n == 1) "1 $noun" else "$n ${noun}s"
    }
}
