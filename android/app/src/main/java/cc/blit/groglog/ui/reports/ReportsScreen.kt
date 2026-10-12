package cc.blit.groglog.ui.reports

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import cc.blit.groglog.ui.containerViewModel

@Composable
fun ReportsScreen(modifier: Modifier = Modifier, viewModel: ReportsViewModel = containerViewModel(::ReportsViewModel)) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(if (state == null) "Reports" else "Reports · ${state?.ledger?.today}")
    }
}
