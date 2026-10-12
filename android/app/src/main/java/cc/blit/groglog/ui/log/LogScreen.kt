package cc.blit.groglog.ui.log

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import cc.blit.groglog.model.CatalogItem
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.DayTotals
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.Units
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.model.abvText
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.shared.DrinkGlyph
import cc.blit.groglog.ui.shared.GrogIcons
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The Log tab: today's drink picker. `onCreateDrink` opens the drink editor with the search text as the name, and
 * `onEditDrink` opens it on a drink; where they are null, the controls that lead there are left out.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogScreen(
    modifier: Modifier = Modifier,
    onCreateDrink: ((String) -> Unit)? = null,
    onEditDrink: ((Drink) -> Unit)? = null,
    viewModel: LogViewModel = viewModel(factory = LogViewModel.factory()),
) {
    Scaffold(
        modifier,
        topBar = {
            TopAppBar(
                title = { Text("Log") },
                actions = {
                    if (onCreateDrink != null) {
                        IconButton(onClick = { onCreateDrink(viewModel.search.trim()) }) {
                            Icon(Icons.Filled.Add, contentDescription = "New drink")
                        }
                    }
                },
                windowInsets = WindowInsets(0),
            )
        },
        contentWindowInsets = WindowInsets(0),
    ) { padding ->
        DrinkPicker(viewModel, Modifier.padding(padding), onCreateDrink, onEditDrink)
    }
}

/** The picker for backfilling another day, over whichever screen asked for it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddDrinkSheet(
    day: DayKey,
    onDismiss: () -> Unit,
    onCreateDrink: ((String) -> Unit)? = null,
    onEditDrink: ((Drink) -> Unit)? = null,
) {
    val viewModel: LogViewModel = viewModel(key = "log-$day", factory = LogViewModel.factory(day))
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                day.localDate.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL)),
                Modifier.weight(1f).semantics { heading() },
                style = MaterialTheme.typography.titleLarge,
            )
            TextButton(onClick = onDismiss) { Text("Done") }
        }
        DrinkPicker(viewModel, Modifier.fillMaxSize(), onCreateDrink, onEditDrink)
    }
}

/**
 * The logging surface: the Log-grid favourites plus anything already logged that day, each a drink in a size, most
 * recently drunk first. Tap logs one; long-press to change the drink, size, strength, time or count.
 */
@Composable
fun DrinkPicker(
    viewModel: LogViewModel,
    modifier: Modifier = Modifier,
    onCreateDrink: ((String) -> Unit)? = null,
    onEditDrink: ((Drink) -> Unit)? = null,
) {
    LifecycleResumeEffect(viewModel) {
        viewModel.appeared()
        onPauseOrDispose {}
    }
    val state by viewModel.state.collectAsStateWithLifecycle()
    var options by remember { mutableStateOf<Serve?>(null) }
    var countingUnits by rememberSaveable { mutableStateOf(false) }
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current

    // Offered after every log; undoing takes back as many as were logged.
    fun confirm(message: String, count: Int) {
        haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        scope.launch {
            snackbar.currentSnackbarData?.dismiss()
            if (snackbar.showSnackbar("Logged $message", actionLabel = "Undo") == SnackbarResult.ActionPerformed) {
                viewModel.undo(count)
            }
        }
    }

    val current = state
    Box(modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            SearchField(
                viewModel.search,
                { viewModel.search = it },
                "Stella, Rioja, pint…",
                Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            if (current != null) {
                PickerGrid(
                    state = current,
                    onTap = { serve ->
                        if (serve.drink.category == DrinkCategory.UNITS) {
                            countingUnits = true
                        } else {
                            viewModel.log(serve)
                            confirm("${serve.drink.name} · ${serve.units.unitsText} u", 1)
                        }
                    },
                    onOptions = { serve -> if (serve.drink.category == DrinkCategory.UNITS) countingUnits = true else options = serve },
                    onAdopt = { item ->
                        viewModel.adopt(item, current.currency)
                        confirm("${item.name} · ${item.units.unitsText} u", 1)
                    },
                    onCreateDrink = onCreateDrink,
                )
            }
        }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
            SnackbarHost(snackbar)
            if (current != null) {
                DaySummaryBar(
                    totals = current.ledger.totals(current.day),
                    status = current.ledger.status(current.day),
                    onUndo = { viewModel.undo() },
                    onAlcoholFree = viewModel::setAlcoholFree,
                )
            }
        }
    }

    val serve = options
    if (serve != null && current != null) {
        LogOptionsSheet(
            base = serve,
            state = current,
            viewModel = viewModel,
            onDismiss = { options = null },
            onEditDrink = onEditDrink,
            onLogged = ::confirm,
        )
    }
    if (countingUnits && current != null) {
        UnitsSheet(
            day = current.day,
            clock = current.clock,
            initialTime = current.suggestedTime,
            onDismiss = { countingUnits = false },
            onLog = { units, time ->
                viewModel.logUnits(units, time)
                confirm("${units.unitsText} u", 1)
            },
        )
    }
}

@Composable
private fun PickerGrid(
    state: LogState,
    onTap: (Serve) -> Unit,
    onOptions: (Serve) -> Unit,
    onAdopt: (CatalogItem) -> Unit,
    onCreateDrink: ((String) -> Unit)?,
) {
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    // Scrolling the grid puts the keyboard away, so the tiles it covered can be reached.
    val dismissKeyboard = remember(keyboard, focus) {
        object : NestedScrollConnection {
            override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
                if (source == NestedScrollSource.UserInput && available.y != 0f) {
                    keyboard?.hide()
                    focus.clearFocus()
                }
                return Offset.Zero
            }
        }
    }
    // Grows with the text size, so the tiles go to fewer columns rather than clipping their names.
    val tileWidth = 104.dp * LocalDensity.current.fontScale.coerceIn(1f, 1.5f)
    val query = state.query.trim()

    LazyVerticalGrid(
        columns = GridCells.Adaptive(tileWidth),
        modifier = Modifier.fillMaxSize().nestedScroll(dismissKeyboard),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 96.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(state.tiles, key = { it.id }) { serve ->
            DrinkTile(
                name = serve.drink.name,
                category = serve.drink.category,
                vessel = serve.vessel,
                volumeMl = serve.volumeMl,
                abv = serve.drink.abv,
                count = state.counts[serve.id] ?: 0,
                pulse = state.pulses[serve.id] ?: 0,
                onClick = { onTap(serve) },
                onLongClick = { onOptions(serve) },
                modifier = if (query.isEmpty()) Modifier.animateItem() else Modifier,
            )
        }
        if (state.catalog.isNotEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }, contentType = "heading") {
                Text("UK drinks", Modifier.padding(top = 12.dp).semantics { heading() }, style = MaterialTheme.typography.titleMedium)
            }
            items(state.catalog, key = { "catalog|${it.id}" }) { item ->
                DrinkTile(
                    name = item.name,
                    category = item.category,
                    vessel = item.vessel,
                    volumeMl = item.volumeMl,
                    abv = item.abv,
                    count = 0,
                    onClick = { onAdopt(item) },
                )
            }
        }
        if (query.isNotEmpty() && state.tiles.isEmpty() && state.catalog.isEmpty()) {
            item(span = { GridItemSpan(maxLineSpan) }, contentType = "empty") {
                NoMatches(query, onCreateDrink)
            }
        }
    }
}

@Composable
private fun NoMatches(query: String, onCreateDrink: ((String) -> Unit)?) {
    Column(
        Modifier.fillMaxWidth().padding(top = 40.dp, start = 16.dp, end = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Filled.Search, contentDescription = null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("No matches for “$query”", style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        Text(
            "Add it as a drink with its own strength and size.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        if (onCreateDrink != null) {
            Button(onClick = { onCreateDrink(query) }, Modifier.padding(top = 8.dp)) { Text("Add “$query”") }
        }
    }
}

/** A rounded search field; the clear button appears once there is something to clear. */
@Composable
internal fun SearchField(query: String, onQueryChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    val focus = LocalFocusManager.current
    Surface(modifier.fillMaxWidth().heightIn(min = 48.dp), shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh) {
        Row(Modifier.padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Search, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Box(Modifier.weight(1f).padding(horizontal = 12.dp), contentAlignment = Alignment.CenterStart) {
                if (query.isEmpty()) {
                    Text(placeholder, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyLarge, maxLines = 1)
                }
                BasicTextField(
                    value = query,
                    onValueChange = onQueryChange,
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Search drinks" },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                    cursorBrush = SolidColor(GrogColors.grog),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { focus.clearFocus() }),
                )
            }
            if (query.isNotEmpty()) {
                IconButton(onClick = { onQueryChange("") }) { Icon(Icons.Filled.Close, contentDescription = "Clear search") }
            } else {
                Spacer(Modifier.size(48.dp))
            }
        }
    }
}

/**
 * One serve on the grid. Each log plays a pour: the tile dips, the glass empties and refills with a tilt, the count
 * badge pops, and the units float off the top.
 */
@Composable
fun DrinkTile(
    name: String,
    category: DrinkCategory,
    vessel: Vessel,
    volumeMl: Double,
    abv: Double,
    count: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    pulse: Int = 0,
    onLongClick: (() -> Unit)? = null,
) {
    val units = Units.of(volumeMl, abv)
    val isUnits = category == DrinkCategory.UNITS
    val scale = remember { Animatable(1f) }
    val fill = remember { Animatable(1f) }
    val tilt = remember { Animatable(0f) }
    val badge = remember { Animatable(1f) }
    val rise = remember { Animatable(1f) }
    // Only a log made while the tile is on screen plays; one scrolled back into view stays still.
    val firstPulse = remember { pulse }
    LaunchedEffect(pulse) {
        if (pulse == firstPulse) return@LaunchedEffect
        launch {
            scale.animateTo(0.92f, tween(90))
            scale.animateTo(1f, spring(dampingRatio = 0.55f, stiffness = Spring.StiffnessMediumLow))
        }
        launch {
            fill.animateTo(0.15f, tween(120))
            fill.animateTo(1f, spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessLow))
        }
        launch {
            tilt.animateTo(-8f, tween(120))
            tilt.animateTo(0f, spring(dampingRatio = 0.5f, stiffness = Spring.StiffnessMediumLow))
        }
        launch {
            badge.snapTo(1f)
            delay(150)
            badge.animateTo(1.3f, tween(100))
            badge.animateTo(1f, spring(dampingRatio = 0.45f, stiffness = Spring.StiffnessMedium))
        }
        launch {
            rise.snapTo(0f)
            rise.animateTo(1f, tween(800))
        }
    }

    val serving = category.serving(vessel, volumeMl, abv)
    val spoken = buildList {
        if (!isUnits) {
            add(vessel.label(volumeMl))
            add(abv.abvText)
            add("${units.unitsText} units")
        }
        if (count > 0) add("$count logged")
    }.joinToString(", ")

    Box(
        modifier
            .graphicsLayer {
                scaleX = scale.value
                scaleY = scale.value
            }
            .clip(TileShape)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            // Its own words rather than the tile's text combined, which would also read the units floating off it.
            .clearAndSetSemantics {
                contentDescription = name
                if (spoken.isNotEmpty()) stateDescription = spoken
                role = Role.Button
                onClick(if (isUnits) "Enter a number of units" else "Log one") { onClick(); true }
                if (onLongClick != null) {
                    onLongClick("Options") { onLongClick(); true }
                    customActions = listOf(CustomAccessibilityAction("Options") { onLongClick(); true })
                }
            },
    ) {
        Surface(shape = TileShape, color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = Modifier.fillMaxWidth()) {
            Column(
                Modifier.padding(vertical = 12.dp, horizontal = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                DrinkGlyph(
                    category,
                    vessel,
                    Modifier
                        .padding(bottom = 4.dp)
                        .height(58.dp)
                        .graphicsLayer {
                            rotationZ = tilt.value
                            transformOrigin = TransformOrigin(0.5f, 1f)
                        },
                    volumeMl = volumeMl,
                    fill = fill.value,
                )
                // A seventh of the catalogue is a brewery's name plus a beer's, and the beer's name is what tells them
                // apart, so the name shrinks to fit before it is cut short.
                val nameStyle = MaterialTheme.typography.titleSmall
                BasicText(
                    name,
                    style = nameStyle.copy(color = MaterialTheme.colorScheme.onSurface, textAlign = TextAlign.Center),
                    maxLines = 2,
                    minLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    autoSize = TextAutoSize.StepBased(minFontSize = nameStyle.fontSize * 0.7f, maxFontSize = nameStyle.fontSize, stepSize = 0.5.sp),
                )
                val servingStyle = MaterialTheme.typography.labelSmall
                BasicText(
                    serving,
                    style = servingStyle.copy(color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    autoSize = TextAutoSize.StepBased(minFontSize = servingStyle.fontSize * 0.8f, maxFontSize = servingStyle.fontSize, stepSize = 0.5.sp),
                )
                Text(
                    if (isUnits) "type it in" else "${units.unitsText} u",
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Bold,
                    color = GrogColors.grog,
                )
            }
        }
        AnimatedVisibility(
            visible = count > 0,
            modifier = Modifier.align(Alignment.TopEnd).padding(6.dp),
            enter = scaleIn() + fadeIn(),
            exit = scaleOut() + fadeOut(),
        ) {
            AnimatedContent(count, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "count") { shown ->
                Text(
                    "×$shown",
                    Modifier
                        .graphicsLayer {
                            scaleX = badge.value
                            scaleY = badge.value
                        }
                        .background(GrogColors.grog, CircleShape)
                        .padding(horizontal = 7.dp, vertical = 3.dp),
                    color = Color.White,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Bold,
                )
            }
        }
        if (rise.value < 1f) {
            Text(
                "+${units.unitsText} u",
                Modifier
                    .align(Alignment.TopCenter)
                    .graphicsLayer {
                        translationY = -44.dp.toPx() * rise.value
                        alpha = 1 - rise.value
                    },
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Black,
                color = GrogColors.grog,
            )
        }
    }
}

private val TileShape = RoundedCornerShape(20.dp)

/** What is logged for the day so far, with undo, or a one-tap alcohol-free mark when nothing is. */
@Composable
fun DaySummaryBar(totals: DayTotals, status: DayStatus, onUndo: () -> Unit, onAlcoholFree: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    if (status == DayStatus.FUTURE) return
    Surface(
        modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp).fillMaxWidth(),
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceContainerHighest,
        shadowElevation = 3.dp,
    ) {
        Row(Modifier.heightIn(min = 52.dp).padding(start = 20.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            val style = MaterialTheme.typography.bodyMedium
            when (status) {
                DayStatus.DRANK -> {
                    Text("${totals.count} ${if (totals.count == 1) "drink" else "drinks"} · ", style = style)
                    AnimatedContent(totals.units.unitsText, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "units") {
                        Text("$it u", style = style, fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = onUndo) { Icon(GrogIcons.Undo, contentDescription = "Undo last drink") }
                }
                DayStatus.ALCOHOL_FREE -> {
                    Icon(GrogIcons.Leaf, contentDescription = null, tint = GrogColors.dry, modifier = Modifier.size(18.dp))
                    Text("Alcohol-free", Modifier.padding(start = 6.dp), style = style, color = GrogColors.dry)
                    Spacer(Modifier.weight(1f))
                    TextButton(onClick = { onAlcoholFree(false) }) { Text("Undo") }
                }
                else -> {
                    Text("Nothing logged", style = style, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.weight(1f))
                    FilledTonalButton(
                        onClick = { onAlcoholFree(true) },
                        colors = ButtonDefaults.filledTonalButtonColors(containerColor = GrogColors.dry.copy(alpha = 0.2f), contentColor = GrogColors.dry),
                        modifier = Modifier.padding(vertical = 4.dp),
                    ) {
                        Icon(GrogIcons.Leaf, contentDescription = null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Alcohol-free")
                    }
                }
            }
        }
    }
}

@Preview(showBackground = true, widthDp = 140)
@Composable
private fun DrinkTilePreview() {
    GrogLogTheme {
        DrinkTile("Staropramen", DrinkCategory.BEER, Vessel.PINT, 568.0, 5.0, count = 2, onClick = {}, modifier = Modifier.padding(16.dp))
    }
}

@Preview(showBackground = true)
@Composable
private fun DaySummaryBarPreview() {
    GrogLogTheme {
        Column {
            DaySummaryBar(DayTotals(units = 7.4, count = 3), DayStatus.DRANK, {}, {})
            DaySummaryBar(DayTotals(), DayStatus.ALCOHOL_FREE, {}, {})
            DaySummaryBar(DayTotals(), DayStatus.TODAY, {}, {})
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun SearchFieldPreview() {
    GrogLogTheme { SearchField("", {}, "Stella, Rioja, pint…", Modifier.padding(16.dp)) }
}
