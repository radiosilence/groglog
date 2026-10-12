package cc.blit.groglog.ui.setup

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation3.runtime.EntryProviderScope
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavKey
import cc.blit.groglog.container
import cc.blit.groglog.data.Settings
import cc.blit.groglog.export.Exporter
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Rates
import cc.blit.groglog.model.Taper
import cc.blit.groglog.ui.SetupRoute
import cc.blit.groglog.ui.containerViewModel
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import cc.blit.groglog.ui.shared.Section
import java.io.File
import java.util.Currency
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.launch

/** Setup's pushed pages, for MainActivity's back stack. A page closes only itself, so a double tap cannot close two. */
fun EntryProviderScope<NavKey>.setupEntries(modifier: Modifier, backStack: NavBackStack<NavKey>) {
    val close = { key: NavKey -> if (backStack.lastOrNull() == key) backStack.removeAt(backStack.lastIndex) }
    entry<SetupRoute.Drinks> { key ->
        val model = containerViewModel { DrinksViewModel(it.database, it.prefs) }
        val groups by model.drinks.collectAsStateWithLifecycle()
        Box(modifier) {
            DrinksPage(
                groups,
                onBack = { close(key) },
                onNew = { backStack.add(SetupRoute.EditDrink()) },
                onEdit = { backStack.add(SetupRoute.EditDrink(it.id.toString())) },
                onHide = model::setHidden,
            )
        }
    }
    entry<SetupRoute.EditDrink> { key ->
        val model = containerViewModel { DrinkEditorViewModel(it.database, it.prefs, key.id?.let(UUID::fromString), key.name) }
        val timesLogged by model.timesLogged.collectAsStateWithLifecycle()
        Box(modifier) { DrinkEditorPage(model, timesLogged, onClose = { close(key) }) }
    }
    entry<SetupRoute.Goal> { key ->
        val model = containerViewModel { GoalViewModel(it.database, it.prefs) }
        Box(modifier) { GoalPage(model, onClose = { close(key) }, onGuidance = { backStack.add(SetupRoute.Guidance) }) }
    }
    entry<SetupRoute.Guidance> { key -> Box(modifier) { GuidancePage(onClose = { close(key) }) } }
}

@Composable
fun SetupScreen(modifier: Modifier = Modifier, reselected: Flow<Unit> = emptyFlow(), onOpen: (NavKey) -> Unit) {
    val context = LocalContext.current
    val model = containerViewModel { SetupViewModel(it.database, it.prefs, it.scope, File(context.cacheDir, "exports")) }
    val container = context.container
    Box(modifier) {
        SetupContent(
            model,
            isDemo = container.isDemo,
            onDemo = container::setDemo,
            onGoal = { onOpen(SetupRoute.Goal) },
            onDrinks = { onOpen(SetupRoute.Drinks) },
            reselected = reselected,
        )
    }
}

@Composable
private fun SetupContent(
    model: SetupViewModel,
    isDemo: Boolean,
    onDemo: (Boolean) -> Unit,
    onGoal: () -> Unit,
    onDrinks: () -> Unit,
    reselected: Flow<Unit>,
) {
    val list = rememberLazyListState()
    LaunchedEffect(reselected) { reselected.collect { list.animateScrollToItem(0) } }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state by model.state.collectAsStateWithLifecycle()
    val notice by model.notice.collectAsStateWithLifecycle()
    val dynamicColour by model.dynamicColour.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }

    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let { model.import(it, context.contentResolver) }
    }
    val saver = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument(Exporter.Kind.JSON.mimeType)) { uri ->
        uri?.let { model.saveBackup(it, context.contentResolver) }
    }

    when (val shown = notice) {
        is Notice.Dialog -> AlertDialog(
            onDismissRequest = model::dismissNotice,
            title = { Text(shown.title) },
            text = { Text(shown.text) },
            confirmButton = { TextButton(onClick = model::dismissNotice) { Text("OK") } },
        )
        is Notice.Brief -> LaunchedEffect(shown) {
            snackbar.showSnackbar(shown.text)
            model.dismissNotice()
        }
        null -> Unit
    }

    val current = state ?: return
    SetupHome(
        settings = current.settings,
        ledger = current.ledger,
        version = remember { versionText(context) },
        developer = remember { context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0 },
        isDemo = isDemo,
        snackbar = snackbar,
        list = list,
        onGoal = onGoal,
        onDrinks = onDrinks,
        onResetPrices = { model.resetPrices() },
        onRolloverHour = { model.setRolloverHour(it) },
        onCurrency = model::setCurrency,
        dynamicColour = dynamicColour,
        onDynamicColour = model::setDynamicColour,
        onExportMarkdown = { scope.launch { share(context, model.exportFile(Exporter.Kind.MARKDOWN)) } },
        onExportBackup = { scope.launch { saver.launch(model.fileName(Exporter.Kind.JSON)) } },
        // Files from cloud drives often arrive without a JSON type, so anything textual is offered.
        onImport = { importer.launch(arrayOf(Exporter.Kind.JSON.mimeType, "text/*", "application/octet-stream")) },
        onDemo = onDemo,
        onRebuild = model::rebuild,
    )
}

/**
 * Hands an export to the share sheet as a file. Plain text is the type chat apps accept, which is where this log is
 * pasted; the text itself is not attached, since a long log would exceed what an intent can carry.
 */
private fun share(context: Context, file: File) {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.exports", file)
    val send = Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_STREAM, uri)
        .putExtra(Intent.EXTRA_TITLE, file.name)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    send.clipData = ClipData.newRawUri(file.name, uri)
    context.startActivity(Intent.createChooser(send, "GrogLog log"))
}

private fun versionText(context: Context): String {
    val info = context.packageManager.getPackageInfo(context.packageName, 0)
    return "GrogLog ${info.versionName} (${PackageInfoCompat.getLongVersionCode(info)})"
}

@Composable
internal fun SetupHome(
    settings: Settings,
    ledger: Ledger,
    version: String,
    developer: Boolean,
    isDemo: Boolean,
    snackbar: SnackbarHostState = remember { SnackbarHostState() },
    list: LazyListState = rememberLazyListState(),
    onGoal: () -> Unit = {},
    onDrinks: () -> Unit = {},
    onResetPrices: () -> Unit = {},
    onRolloverHour: (Int) -> Unit = {},
    onCurrency: (String) -> Unit = {},
    dynamicColour: Boolean = false,
    onDynamicColour: (Boolean) -> Unit = {},
    onExportMarkdown: () -> Unit = {},
    onExportBackup: () -> Unit = {},
    onImport: () -> Unit = {},
    onDemo: (Boolean) -> Unit = {},
    onRebuild: () -> Unit = {},
) {
    var dialog by rememberSaveable { mutableStateOf<String?>(null) }
    val uri = LocalUriHandler.current

    SetupPage(title = "Setup", large = true, snackbar = snackbar, list = list) {
        item(key = "goal") {
            // The guidance the pace limits come from assumes a clinician judged the person suitable and reviews them as
            // they go. GrogLog does neither, and the copy must not suggest otherwise.
            Section(
                footer = "Choose a rate of reduction to set a daily and weekly budget.\n\nGrogLog does not provide medical advice. It is intended to help you follow a plan agreed with your GP or alcohol service. If you are dependent on alcohol, do not stop suddenly without medical support.",
            ) {
                SettingsRow("Goal", value = goalSummary(settings.goal, ledger), valueColor = GrogColors.grog, onClick = onGoal)
            }
        }
        item(key = "log") {
            Section(footer = "Drinks after midnight count towards the evening before.") {
                SettingsRow("Drinks", chevron = true, onClick = onDrinks)
                RowDivider()
                SettingsRow("Reset prices to the catalogue", onClick = { dialog = "prices" })
                RowDivider()
                SettingsRow("Day ends at", value = hourLabel(settings.rolloverHour, settings.rolloverHour), onClick = { dialog = "hour" })
                RowDivider()
                SettingsRow("Currency", value = settings.currency, onClick = { dialog = "currency" })
            }
        }
        item(key = "health") { HealthSettings(Modifier) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            item(key = "appearance") {
                Section(title = "Appearance") {
                    SwitchRow(
                        "Wallpaper colours",
                        checked = dynamicColour,
                        onChange = onDynamicColour,
                        supporting = "Buttons and controls take their colours from your wallpaper. Charts and the calendar keep GrogLog's own, since their colours carry meaning.",
                    )
                }
            }
        }
        item(key = "data") {
            Section(
                title = "Data",
                footer = "Your log stays on this phone, and in your Google account's device backup if that is on. Importing a backup adds to your log and never overwrites it.",
            ) {
                SettingsRow("Export for an LLM (Markdown)", supporting = "Shares a readable log to paste into a chat.", onClick = onExportMarkdown)
                RowDivider()
                SettingsRow("Export backup (JSON)", supporting = "Saves everything to a file, to import here or on an iPhone.", onClick = onExportBackup)
                RowDivider()
                SettingsRow("Import backup", onClick = onImport)
            }
        }
        item(key = "about") {
            Section(footer = version) {
                LinkRow("Privacy policy", "https://groglog.io/privacy.html")
                RowDivider()
                LinkRow("Support", "https://groglog.io/support.html")
            }
        }
        if (developer) {
            item(key = "developer") {
                Section(
                    title = "Developer",
                    footer = "Replaces your log with four months of sample data, held in memory. Your own log returns when this is turned off. Changing it restarts the app.",
                ) {
                    SwitchRow("Demo mode", checked = isDemo, onChange = onDemo)
                    RowDivider()
                    SettingsRow("Rebuild daily totals", onClick = onRebuild)
                }
            }
        }
    }

    when (dialog) {
        "prices" -> AlertDialog(
            onDismissRequest = { dialog = null },
            title = { Text("Reset prices to the catalogue?") },
            text = { Text("Every drink and Log tile returns to its catalogue price, including any you have changed. Drinks already logged keep the price you paid.") },
            confirmButton = {
                TextButton(onClick = {
                    dialog = null
                    onResetPrices()
                }) { Text("Reset prices", color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { dialog = null }) { Text("Cancel") } },
        )
        "hour" -> ChoiceDialog(
            title = "Day ends at",
            options = (0..8).toList(),
            selected = settings.rolloverHour,
            label = { hourLabel(it, settings.rolloverHour) },
            onSelect = {
                dialog = null
                onRolloverHour(it)
            },
            onDismiss = { dialog = null },
        )
        "currency" -> ChoiceDialog(
            title = "Currency",
            options = Rates.currencies,
            selected = settings.currency,
            label = { code -> runCatching { "$code · ${Currency.getInstance(code).displayName}" }.getOrDefault(code) },
            onSelect = {
                dialog = null
                onCurrency(it)
            },
            onDismiss = { dialog = null },
        )
    }
}

private fun hourLabel(hour: Int, rolloverHour: Int) = DayClock(rolloverHour).hourLabel((hour - rolloverHour).toDouble())

@Composable
private fun <T> ChoiceDialog(title: String, options: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            val state = rememberLazyListState(initialFirstVisibleItemIndex = (options.indexOf(selected) - 2).coerceAtLeast(0))
            LazyColumn(Modifier.heightIn(max = 420.dp), state = state) {
                items(options) { option ->
                    ListItem(
                        headlineContent = { Text(label(option)) },
                        leadingContent = { RadioButton(selected = option == selected, onClick = null) },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        modifier = Modifier.selectable(selected = option == selected, role = Role.RadioButton) { onSelect(option) },
                    )
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** How a page leaves: back to the page before, or closed without saving. */
internal sealed interface PageNavigation {
    val action: () -> Unit

    data class Back(override val action: () -> Unit) : PageNavigation
    data class Close(override val action: () -> Unit) : PageNavigation
}

/**
 * A Setup page: a top bar and a scrolling list. The tab's own scaffold already keeps clear of the status bar, so the top
 * bar takes no insets of its own.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SetupPage(
    title: String,
    navigation: PageNavigation? = null,
    large: Boolean = false,
    snackbar: SnackbarHostState? = null,
    actions: @Composable () -> Unit = {},
    list: LazyListState = rememberLazyListState(),
    content: LazyListScope.() -> Unit,
) {
    val behavior = if (large) TopAppBarDefaults.exitUntilCollapsedScrollBehavior() else TopAppBarDefaults.pinnedScrollBehavior()
    val icon = @Composable {
        when (navigation) {
            is PageNavigation.Back -> IconButton(onClick = navigation.action) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
            }
            is PageNavigation.Close -> IconButton(onClick = navigation.action) {
                Icon(Icons.Filled.Close, contentDescription = "Cancel")
            }
            null -> Unit
        }
    }
    Scaffold(
        modifier = Modifier.nestedScroll(behavior.nestedScrollConnection),
        contentWindowInsets = WindowInsets(0),
        snackbarHost = { snackbar?.let { SnackbarHost(it) } },
        topBar = {
            val heading = @Composable { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            if (large) {
                LargeTopAppBar(title = heading, navigationIcon = icon, actions = { actions() }, scrollBehavior = behavior)
            } else {
                TopAppBar(title = heading, navigationIcon = icon, actions = { actions() }, scrollBehavior = behavior)
            }
        },
    ) { padding ->
        LazyColumn(
            // The keyboard rises over the tab bar, so only the part of it above the system bar needs room.
            Modifier.fillMaxSize().padding(padding).consumeWindowInsets(WindowInsets.navigationBars).imePadding(),
            state = list,
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            content = content,
        )
    }
}

@Composable
internal fun SettingsRow(
    title: String,
    modifier: Modifier = Modifier,
    value: String? = null,
    valueColor: Color = Color.Unspecified,
    supporting: String? = null,
    icon: ImageVector? = null,
    trailingIcon: ImageVector? = null,
    chevron: Boolean = false,
    destructive: Boolean = false,
    enabled: Boolean = true,
    onClickLabel: String? = null,
    onClick: () -> Unit,
) {
    val tint = if (destructive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
    val accent = if (valueColor == Color.Unspecified) MaterialTheme.colorScheme.onSurfaceVariant else valueColor
    val trailing = trailingIcon ?: if (chevron) Icons.AutoMirrored.Filled.KeyboardArrowRight else null
    ListItem(
        headlineContent = { Text(title, color = tint) },
        supportingContent = supporting?.let { { Text(it) } },
        leadingContent = icon?.let { { Icon(it, contentDescription = null, tint = tint) } },
        trailingContent = if (value == null && trailing == null) null else ({
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (value != null) Text(value, style = MaterialTheme.typography.bodyLarge, color = accent)
                if (trailing != null) Icon(trailing, contentDescription = null, tint = accent, modifier = Modifier.padding(start = 4.dp))
            }
        }),
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = modifier
            .clickable(enabled = enabled, onClickLabel = onClickLabel, role = Role.Button, onClick = onClick)
            .alpha(if (enabled) 1f else 0.38f),
    )
}

@Composable
internal fun SwitchRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, supporting: String? = null) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = supporting?.let { { Text(it) } },
        trailingContent = { Switch(checked = checked, onCheckedChange = null) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.toggleable(value = checked, role = Role.Switch, onValueChange = onChange),
    )
}

@Composable
internal fun LinkRow(title: String, url: String) {
    val uri = LocalUriHandler.current
    SettingsRow(title, valueColor = MaterialTheme.colorScheme.primary, onClick = { uri.openUri(url) }, onClickLabel = "Open in browser")
}

@Composable
internal fun RowDivider() {
    HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.surface)
}

@Preview(name = "Setup")
@Composable
private fun SetupPreview() {
    GrogLogTheme {
        Surface {
            SetupHome(
                settings = Settings(currency = "GBP", goal = Goal(isEnabled = true, taper = Taper.DYNAMIC, baselineWeekly = 210.0)),
                ledger = Ledger(emptyList(), DayClock(5)),
                version = "GrogLog 1.0 (1)",
                developer = true,
                isDemo = false,
            )
        }
    }
}
