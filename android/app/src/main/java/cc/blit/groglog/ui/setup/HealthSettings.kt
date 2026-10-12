package cc.blit.groglog.ui.setup

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import cc.blit.groglog.AppContainer
import cc.blit.groglog.container
import cc.blit.groglog.data.HealthSwitches
import cc.blit.groglog.data.health.Health
import cc.blit.groglog.ui.theme.GrogLogTheme
import cc.blit.groglog.ui.shared.Section
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Whether Health Connect can be used here, and if not, whether installing or updating it would fix that. */
enum class HealthConnectStatus { AVAILABLE, NEEDS_INSTALL, UNSUPPORTED }

/** What the three switches show: on only while both the setting and its permission stand. */
data class HealthSettingsState(
    val status: HealthConnectStatus = HealthConnectStatus.UNSUPPORTED,
    val copies: Boolean = false,
    val heart: Boolean = false,
    val sleep: Boolean = false,
)

class HealthSettingsViewModel(private val container: AppContainer, private val status: () -> HealthConnectStatus) : ViewModel() {
    private val health = container.health
    private val prefs = container.prefs

    /** Re-read on resume: permissions can be withdrawn in Health Connect while the app is away. */
    private val granted = MutableStateFlow<Set<String>>(emptySet())
    private val available = MutableStateFlow(HealthConnectStatus.UNSUPPORTED)

    val state: StateFlow<HealthSettingsState> = combine(prefs.health, granted, available) { switches, granted, status ->
        HealthSettingsState(
            status = status,
            copies = switches.copies && granted.containsAll(Health.COPY),
            heart = switches.heart && Health.HEART.any { it in granted },
            sleep = switches.sleep && granted.containsAll(Health.SLEEP),
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HealthSettingsState())

    fun refresh() {
        available.value = status()
        viewModelScope.launch { granted.value = health.granted().orEmpty() }
    }

    fun copyPermissions() = Health.COPY

    fun heartPermissions() = health.withHistory(Health.HEART)

    fun sleepPermissions() = health.withHistory(Health.SLEEP)

    /** After the permission sheet: copying starts with the whole log, or stays off if writing was refused. */
    fun copyGranted(result: Set<String>) {
        granted.value += result
        if (!result.containsAll(Health.COPY)) return
        // The container's scope, so leaving Setup does not stop a long log half-copied.
        container.scope.launch {
            update { it.copy(copies = true) }
            health.mirror(null)
        }
    }

    fun stopCopying() {
        container.scope.launch {
            update { it.copy(copies = false) }
            health.removeMirror()
        }
    }

    fun heartGranted(result: Set<String>) {
        granted.value += result
        viewModelScope.launch { update { it.copy(heart = Health.HEART.any { permission -> permission in result }) } }
    }

    fun sleepGranted(result: Set<String>) {
        granted.value += result
        viewModelScope.launch { update { it.copy(sleep = result.containsAll(Health.SLEEP)) } }
    }

    fun stopReading(heart: Boolean) {
        viewModelScope.launch { update { if (heart) it.copy(heart = false) else it.copy(sleep = false) } }
    }

    private suspend fun update(change: (HealthSwitches) -> HealthSwitches) = prefs.setHealth(change(prefs.health.first()))

    companion object {
        fun status(context: Context) = when (HealthConnectClient.getSdkStatus(context)) {
            HealthConnectClient.SDK_AVAILABLE -> HealthConnectStatus.AVAILABLE
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> HealthConnectStatus.NEEDS_INSTALL
            else -> HealthConnectStatus.UNSUPPORTED
        }
    }
}

/**
 * Setup's Health Connect switches: copying drinks' calories out, and reading heart readings and sleep in. Each is its
 * own permission in Health Connect, asked for when the switch is turned on. Nothing is shown where Health Connect
 * cannot run.
 */
@Composable
fun HealthSettings(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val model = viewModel { HealthSettingsViewModel(context.container) { HealthSettingsViewModel.status(context) } }
    val state by model.state.collectAsStateWithLifecycle()
    LifecycleResumeEffect(model) {
        model.refresh()
        onPauseOrDispose {}
    }
    val contract = PermissionController.createRequestPermissionResultContract()
    val copy = rememberLauncherForActivityResult(contract, model::copyGranted)
    val heart = rememberLauncherForActivityResult(contract, model::heartGranted)
    val sleep = rememberLauncherForActivityResult(contract, model::sleepGranted)
    HealthSettingsContent(
        state = state,
        onCopies = { if (it) copy.launch(model.copyPermissions()) else model.stopCopying() },
        onHeart = { if (it) heart.launch(model.heartPermissions()) else model.stopReading(heart = true) },
        onSleep = { if (it) sleep.launch(model.sleepPermissions()) else model.stopReading(heart = false) },
        onInstall = { context.openHealthConnectListing() },
        onManage = { context.openHealthConnect() },
        modifier = modifier,
    )
}

@Composable
internal fun HealthSettingsContent(
    state: HealthSettingsState,
    onCopies: (Boolean) -> Unit,
    onHeart: (Boolean) -> Unit,
    onSleep: (Boolean) -> Unit,
    onInstall: () -> Unit,
    onManage: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (state.status == HealthConnectStatus.UNSUPPORTED) return
    Section(modifier, title = "Health Connect") {
        if (state.status == HealthConnectStatus.NEEDS_INSTALL) {
            SettingsRow(
                "Install Health Connect",
                supporting = "Copying calories, heart readings and sleep all go through Health Connect, which this phone needs from Google Play first.",
                onClick = onInstall,
            )
            return@Section
        }
        SwitchRow(
            "Copy to Health Connect",
            state.copies,
            onCopies,
            "The calories in your drinks are added to Health Connect as you log them, as nutrition. Health Connect has no record for alcohol itself, so the drinks are not. Turning this off removes them.",
        )
        SwitchRow(
            "Heart readings from Health Connect",
            state.heart,
            onHeart,
            "Shows your heart rate during sleep, resting heart rate and HRV on Reports, alongside what you drank the night before. Requires a watch or ring that records them in Health Connect.",
        )
        SwitchRow(
            "Sleep from Health Connect",
            state.sleep,
            onSleep,
            "Shows each night's sleep by stage on Reports, alongside what you drank the evening before. Requires a watch or ring that records sleep in Health Connect.",
        )
        SettingsRow("Manage in Health Connect", supporting = "See what GrogLog has written, or withdraw its permissions.", onClick = onManage)
    }
}

private fun Context.openHealthConnect() {
    try {
        startActivity(HealthConnectClient.getHealthConnectManageDataIntent(this).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        openHealthConnectListing()
    }
}

private fun Context.openHealthConnectListing() {
    val listing = "market://details?id=${Health.PROVIDER}&url=healthconnect%3A%2F%2Fonboarding".toUri()
    try {
        startActivity(Intent(Intent.ACTION_VIEW, listing).setPackage("com.android.vending").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        startActivity(Intent(Intent.ACTION_VIEW, "https://play.google.com/store/apps/details?id=${Health.PROVIDER}".toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

@Preview(showBackground = true)
@Composable
private fun HealthSettingsPreview() {
    GrogLogTheme {
        HealthSettingsContent(HealthSettingsState(HealthConnectStatus.AVAILABLE, copies = true, heart = true), {}, {}, {}, {}, {})
    }
}

@Preview(showBackground = true)
@Composable
private fun HealthSettingsInstallPreview() {
    GrogLogTheme {
        HealthSettingsContent(HealthSettingsState(HealthConnectStatus.NEEDS_INSTALL), {}, {}, {}, {}, {})
    }
}
