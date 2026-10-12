package cc.blit.groglog.ui.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cc.blit.groglog.AppContainer
import cc.blit.groglog.ui.LedgerState
import cc.blit.groglog.ui.ledgerState
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

class ReportsViewModel(private val container: AppContainer) : ViewModel() {
    /** Null until the first read lands. */
    val state: StateFlow<LedgerState?> =
        container.ledgerState().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)
}
