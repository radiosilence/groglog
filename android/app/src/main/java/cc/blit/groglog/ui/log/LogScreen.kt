package cc.blit.groglog.ui.log

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
fun LogScreen(modifier: Modifier = Modifier, viewModel: LogViewModel = containerViewModel(::LogViewModel)) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(if (state == null) "Log" else "Log · ${state?.ledger?.today}")
    }
}
