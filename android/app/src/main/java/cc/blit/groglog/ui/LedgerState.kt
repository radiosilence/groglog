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

/** The settings and every day's totals, which most screens start from. */
data class LedgerState(val settings: Settings, val ledger: Ledger)

/** Rebuilt on each commit to `day` and on each settings change: a few hundred rows a year, so cheap to redo. */
fun AppContainer.ledgerState(): Flow<LedgerState> =
    combine(prefs.settings, queries.days()) { settings, days -> LedgerState(settings, Ledger(days, settings.clock)) }

/** A screen's ViewModel, made with the app's container and scoped to its navigation entry. */
@Composable
inline fun <reified VM : ViewModel> containerViewModel(crossinline create: (AppContainer) -> VM): VM =
    viewModel(factory = viewModelFactory { initializer { create(this[APPLICATION_KEY]!!.container) } })
