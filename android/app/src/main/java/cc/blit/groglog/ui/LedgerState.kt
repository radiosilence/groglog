package cc.blit.groglog.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.compose.runtime.Composable
import cc.blit.groglog.AppContainer
import cc.blit.groglog.container
import cc.blit.groglog.data.Settings
import cc.blit.groglog.model.Ledger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.createSavedStateHandle
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** The settings and every day's totals, which most screens start from. */
data class LedgerState(val settings: Settings, val ledger: Ledger)

/** Rebuilt on each commit to `day` and on each settings change: a few hundred rows a year, so cheap to redo. */
fun AppContainer.ledgerState(): Flow<LedgerState> =
    combine(prefs.settings, queries.days()) { settings, days -> LedgerState(settings, Ledger(days, settings.clock)) }

/** A screen's ViewModel, made with the app's container and scoped to its navigation entry. */
@Composable
inline fun <reified VM : ViewModel> containerViewModel(crossinline create: (AppContainer) -> VM): VM = containerViewModel(null, create)

/** As above, with `key` telling apart several of one type in the same entry, such as a sheet's beside its screen's. */
@Composable
inline fun <reified VM : ViewModel> containerViewModel(key: String?, crossinline create: (AppContainer) -> VM): VM =
    viewModel(key = key, factory = viewModelFactory { initializer { create(this[APPLICATION_KEY]!!.container) } })

/**
 * As `containerViewModel`, for a page whose draft must outlive the page leaving the screen and the process being
 * stopped: the ViewModel is given its entry's `SavedStateHandle`.
 */
@Composable
inline fun <reified VM : ViewModel> savedViewModel(crossinline create: (AppContainer, SavedStateHandle) -> VM): VM =
    viewModel(factory = viewModelFactory { initializer { create(this[APPLICATION_KEY]!!.container, createSavedStateHandle()) } })

/**
 * A text field whose text is kept in the handle under `key` as it is typed, starting from what was kept there. The
 * owner fills it from the database only when nothing was kept, so a restored draft is not overwritten.
 */
fun SavedStateHandle?.textField(key: String, scope: CoroutineScope, initial: String = ""): TextFieldState {
    val handle = this ?: return TextFieldState(initial)
    val state = TextFieldState(handle.get<String>(key) ?: initial)
    scope.launch { snapshotFlow { state.text.toString() }.collect { handle[key] = it } }
    return state
}
