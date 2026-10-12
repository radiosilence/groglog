package cc.blit.groglog.ui.day

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
fun DayScreen(modifier: Modifier = Modifier, viewModel: DayViewModel = containerViewModel(::DayViewModel)) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Text(if (state == null) "Day" else "Day · ${state?.ledger?.today}")
    }
}
