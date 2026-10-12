package cc.blit.groglog.ui.day

import android.content.res.Configuration
import android.text.format.DateFormat
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLocale
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import cc.blit.groglog.data.Settings
import cc.blit.groglog.model.Day
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.DayTotals
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.model.kcalText
import cc.blit.groglog.model.money
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.containerViewModel
import cc.blit.groglog.ui.log.AddDrinkSheet
import cc.blit.groglog.ui.log.PourEditor
import cc.blit.groglog.ui.shared.DrinkGlyph
import cc.blit.groglog.ui.shared.GrogIcons
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import cc.blit.groglog.ui.shared.Section
import java.util.Date
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

/** The Day tab: today, with previous and next. Choosing the tab again comes back to today. */
@Composable
fun DayScreen(
    modifier: Modifier = Modifier,
    reselected: Flow<Unit> = emptyFlow(),
    onSetGoal: () -> Unit = {},
    onCreateDrink: ((String) -> Unit)? = null,
    onEditDrink: ((Drink) -> Unit)? = null,
    viewModel: DayViewModel = containerViewModel { DayViewModel(it) },
) {
    LaunchedEffect(reselected) { reselected.collect { viewModel.show(null) } }
    DayPager(viewModel, onSetGoal, onCreateDrink, onEditDrink, modifier)
}

/** A day opened from the calendar, with previous and next and a way back. */
@Composable
fun CalendarDayScreen(
    day: DayKey,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    onSetGoal: () -> Unit = {},
    onCreateDrink: ((String) -> Unit)? = null,
    onEditDrink: ((Drink) -> Unit)? = null,
    viewModel: DayViewModel = containerViewModel { DayViewModel(it, day) },
) {
    DayPager(viewModel, onSetGoal, onCreateDrink, onEditDrink, modifier, onBack)
}

/** A day with previous and next, for the Day tab and for a day opened from the calendar, which passes `onBack`. */
@Composable
fun DayPager(
    model: DayViewModel,
    onSetGoal: () -> Unit,
    onCreateDrink: ((String) -> Unit)?,
    onEditDrink: ((Drink) -> Unit)?,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
) {
    val state = model.state.collectAsStateWithLifecycle().value
    if (state == null) {
        Box(modifier.fillMaxSize())
        return
    }
    val haptics = LocalHapticFeedback.current
    DayPage(
        state = state,
        modifier = modifier,
        onBack = onBack,
        onPrevious = model::previous,
        onNext = model::next,
        onSetGoal = onSetGoal,
        onAlcoholFree = { dry ->
            if (dry) haptics.performHapticFeedback(HapticFeedbackType.Confirm)
            model.setAlcoholFree(dry, state.day)
        },
        onSpend = { model.setSpend(it, state.day) },
        onDelete = model::delete,
        onCreateDrink = onCreateDrink,
        onEditDrink = onEditDrink,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DayPage(
    state: DayState,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    onPrevious: () -> Unit = {},
    onNext: () -> Unit = {},
    onSetGoal: () -> Unit = {},
    onAlcoholFree: (Boolean) -> Unit = {},
    onSpend: (Double?) -> Unit = {},
    onDelete: (Pour) -> Unit = {},
    onCreateDrink: ((String) -> Unit)? = null,
    onEditDrink: ((Drink) -> Unit)? = null,
) {
    var adding by rememberSaveable { mutableStateOf(false) }
    var settingSpend by rememberSaveable { mutableStateOf(false) }
    var editing by rememberSaveable { mutableStateOf<String?>(null) }
    val scroll = TopAppBarDefaults.pinnedScrollBehavior()
    val currency = state.settings.currency

    Scaffold(
        modifier = modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            TopAppBar(
                title = { Text(state.title(LocalLocale.current.platformLocale)) },
                navigationIcon = {
                    if (onBack != null) {
                        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                    }
                },
                actions = {
                    IconButton(onClick = onPrevious) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Previous day") }
                    IconButton(onClick = onNext, enabled = !state.isToday) {
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Next day")
                    }
                },
                scrollBehavior = scroll,
            )
        },
        floatingActionButton = {
            if (state.status != DayStatus.FUTURE) {
                ExtendedFloatingActionButton(
                    onClick = { adding = true },
                    icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                    text = { Text("Add drinks") },
                    containerColor = GrogColors.grog,
                    contentColor = Color.Black,
                )
            }
        },
    ) { padding ->
        // Another day is the same layout with other figures, so paging fades rather than slides.
        AnimatedContent(state, contentKey = { it.day }, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "day") { shown ->
            LazyColumn(
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding() + 4.dp, bottom = padding.calculateBottomPadding() + 96.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
                dayContent(shown, onSetGoal, onAlcoholFree, onDelete, onSpend = { settingSpend = true }, onEdit = { editing = it.id.toString() })
            }
        }
    }

    if (adding) {
        AddDrinkSheet(state.day, onDismiss = { adding = false }, onCreateDrink, onEditDrink)
    }
    if (settingSpend) {
        SpendSheet(
            derived = state.ledger.derivedSpend(state.day),
            override = state.spendOverride,
            currency = currency,
            onSave = {
                onSpend(it)
                settingSpend = false
            },
            onDismiss = { settingSpend = false },
        )
    }
    state.drinks.firstOrNull { it.id.toString() == editing }?.let { entry ->
        PourEditor(entry, state.day, onDismiss = { editing = null }, onEditDrink = onEditDrink)
    }
}

private fun LazyListScope.dayContent(
    state: DayState,
    onSetGoal: () -> Unit,
    onAlcoholFree: (Boolean) -> Unit,
    onDelete: (Pour) -> Unit,
    onSpend: () -> Unit,
    onEdit: (Entry) -> Unit,
) {
    val status = state.status
    val currency = state.settings.currency
    item { TotalsHeader(state.totals, state.budget, currency) }
    item {
        Section {
            val locale = LocalLocale.current.platformLocale
            val chart = remember(state, locale) { dayChart(state.day, state.ledger, state.budget, state.entries, state.now, locale) }
            DayChart(chart, state.now, Modifier.padding(16.dp))
        }
    }
    item {
        val budget = state.budget
        when {
            budget != null -> Section(title = "Budget") { BudgetBar(state.totals.units, budget, Modifier.padding(16.dp)) }
            state.settings.goal.isEnabled -> Section(title = "Budget") {
                Text(
                    "No budget yet. It is worked out from the days logged before this one.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(16.dp),
                )
            }
            else -> Section {
                TextButton(onClick = onSetGoal, modifier = Modifier.padding(horizontal = 4.dp)) { Text("Set a goal to get a daily budget") }
            }
        }
    }
    if (status == DayStatus.DRANK || state.spendOverride != null) {
        item {
            Section(
                footer = if (state.spendOverride == null) {
                    "Added up from what each drink cost. Set the day's total instead if you would rather not price every round."
                } else {
                    "Set by hand for the day. What the drinks cost is ignored until you clear it."
                },
            ) {
                ListItem(
                    headlineContent = { Text("Spent") },
                    trailingContent = {
                        Text(
                            state.totals.cost.money(currency),
                            style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"),
                            color = if (state.spendOverride == null) MaterialTheme.colorScheme.onSurfaceVariant else GrogColors.grog,
                        )
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    modifier = Modifier.clickable(onClickLabel = "Set the day's spend", onClick = onSpend),
                )
            }
        }
    }
    when (status) {
        DayStatus.DRANK -> item {
            Section(title = "Drinks") {
                state.drinks.forEachIndexed { index, entry ->
                    if (index > 0) HorizontalDivider(Modifier.padding(start = 72.dp))
                    SwipeToDelete(onDelete = { onDelete(entry.pour) }) {
                        PourRow(entry, currency, Modifier.clickable(onClickLabel = "Edit") { onEdit(entry) })
                    }
                }
            }
        }
        DayStatus.ALCOHOL_FREE -> item {
            Section {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(GrogIcons.Leaf, contentDescription = null, tint = GrogColors.dry)
                    Spacer(Modifier.width(12.dp))
                    Text("Alcohol-free day", style = MaterialTheme.typography.titleMedium, color = GrogColors.dry)
                }
                TextButton(onClick = { onAlcoholFree(false) }, modifier = Modifier.padding(start = 4.dp, bottom = 4.dp)) {
                    Text("Not alcohol-free after all", color = MaterialTheme.colorScheme.error)
                }
            }
        }
        DayStatus.TODAY, DayStatus.UNLOGGED, DayStatus.UNTRACKED -> item {
            Section(
                footer = if (status == DayStatus.UNLOGGED) {
                    "Nothing logged. Mark it dry or add what you had. Unmarked days stay \"not logged\" rather than counting as dry."
                } else {
                    "Days only count as dry when you say so."
                },
            ) {
                FilledTonalButton(onClick = { onAlcoholFree(true) }, modifier = Modifier.fillMaxWidth().padding(12.dp)) {
                    Icon(GrogIcons.Leaf, contentDescription = null, tint = GrogColors.dry, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(if (status == DayStatus.TODAY) "Mark today alcohol-free" else "It was alcohol-free")
                }
            }
        }
        DayStatus.FUTURE -> Unit
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeToDelete(onDelete: () -> Unit, content: @Composable () -> Unit) {
    val swipe = rememberSwipeToDismissBoxState()
    SwipeToDismissBox(
        state = swipe,
        enableDismissFromStartToEnd = false,
        onDismiss = { if (it == SwipeToDismissBoxValue.EndToStart) onDelete() },
        backgroundContent = {
            Box(
                Modifier.fillMaxSize().background(MaterialTheme.colorScheme.errorContainer).padding(horizontal = 20.dp),
                contentAlignment = Alignment.CenterEnd,
            ) { Icon(Icons.Filled.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.onErrorContainer) }
        },
        modifier = Modifier.semantics {
            customActions = listOf(
                CustomAccessibilityAction("Delete") {
                    onDelete()
                    true
                },
            )
        },
    ) {
        Box(Modifier.background(MaterialTheme.colorScheme.surfaceContainer)) { content() }
    }
}

/** The day's units large, coloured by how they stand against the budget, with calories and cost beside them. */
@Composable
internal fun TotalsHeader(totals: DayTotals, budget: Double?, currency: String, modifier: Modifier = Modifier) {
    // Stacked at the largest text sizes, where the units and the figures beside them no longer fit a row.
    val stacked = LocalDensity.current.fontScale >= 1.5f
    val units by animateFloatAsState(totals.units.toFloat(), label = "units")
    val figure = @Composable {
        Column {
            Text(
                units.toDouble().unitsText,
                style = MaterialTheme.typography.displayLarge.copy(fontSize = 52.sp, lineHeight = 56.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"),
                color = if (totals.units > 0) GrogColors.heat(totals.units, budget) else MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
            Text(budget?.let { "units of ${it.unitsText} budget" } ?: "units", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    val figures = @Composable {
        val style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum")
        Column(horizontalAlignment = if (stacked) Alignment.Start else Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("${totals.kcal.kcalText} kcal", style = style, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(totals.cost.money(currency), style = style, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (stacked) {
        Column(modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            figure()
            figures()
        }
    } else {
        Row(modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.Bottom) {
            figure()
            Spacer(Modifier.weight(1f))
            Box(Modifier.padding(bottom = 2.dp)) { figures() }
        }
    }
}

/** What remains of the day's budget, draining as drinks are logged rather than filling up. */
@Composable
internal fun BudgetBar(used: Double, budget: Double, modifier: Modifier = Modifier) {
    val left = budget - used
    val fraction = (left / budget).coerceIn(0.0, 1.0)
    val color = when {
        left < 0 -> GrogColors.over
        fraction < 0.25 -> GrogColors.grog
        else -> GrogColors.dry
    }
    val shown by animateFloatAsState(fraction.toFloat(), label = "budget")
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                if (left < 0) "${(-left).unitsText} u over" else "${left.unitsText} u left",
                style = MaterialTheme.typography.titleMedium.copy(fontFeatureSettings = "tnum"),
                color = color,
            )
            Spacer(Modifier.weight(1f))
            Text("of ${budget.unitsText} u", style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Box(Modifier.fillMaxWidth().height(10.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHighest)) {
            Box(
                Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(shown)
                    .clip(CircleShape)
                    .background(Brush.verticalGradient(listOf(color.copy(alpha = 0.8f), color))),
            )
        }
    }
}

@Composable
internal fun PourRow(entry: Entry, currency: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val time = remember(entry.timestamp) { DateFormat.getTimeFormat(context).format(Date.from(entry.timestamp)) }
    ListItem(
        leadingContent = { DrinkGlyph(entry.category, entry.vessel, Modifier.size(40.dp), entry.volumeMl) },
        headlineContent = { Text(entry.name, fontWeight = FontWeight.Medium) },
        supportingContent = { Text(entry.category.serving(entry.vessel, entry.volumeMl, entry.abv)) },
        trailingContent = {
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    "${entry.units.unitsText} u",
                    style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"),
                    color = MaterialTheme.colorScheme.onSurface,
                )
                // What it cost sits beside when it was drunk, so a round reads as both at a glance. A drink with no
                // price says nothing rather than £0.00, which reads as free rather than unpriced.
                Text(if (entry.price > 0) "${entry.price.money(currency)} · $time" else time, style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = "tnum"))
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = modifier,
    )
}

/** A fortnight of drinking ending on `day`, for previews and screenshots. */
internal fun sampleDayState(day: DayKey? = null, dry: Boolean = false): DayState {
    val base = Settings(currency = "GBP")
    val clock = base.clock
    val shown = day ?: clock.today
    val settings = base.copy(goal = Goal(isEnabled = true, baselineWeekly = 42.0, targetWeekly = 28.0, start = clock.start(shown - 10)))
    val beer = Drink(name = "Staropramen", category = DrinkCategory.BEER, abv = 5.0, vessel = Vessel.PINT, volumeMl = 568.0, price = 6.5)
    val wine = Drink(name = "House red", category = DrinkCategory.RED_WINE, abv = 13.0, vessel = Vessel.WINE_GLASS, volumeMl = 175.0, price = 8.0)
    fun entry(drink: Drink, on: DayKey, hours: Double) = Entry(
        Pour(drinkId = drink.id, timestamp = clock.start(on).plusSeconds((hours * 3600).toLong()), day = on.number, vessel = drink.vessel, volumeMl = drink.volumeMl, price = drink.price),
        drink,
    )
    // A fortnight of mixed nights: some inside the budget, some over, one dry and one never logged.
    val entries = (13 downTo 0).flatMap { back ->
        val on = shown - back
        when {
            back == 0 && dry -> emptyList()
            back == 3 || back == 5 -> emptyList()
            back % 4 == 1 -> listOf(entry(beer, on, 13.0))
            back % 4 == 2 -> listOf(entry(beer, on, 12.5), entry(beer, on, 14.0), entry(wine, on, 16.0), entry(wine, on, 17.5))
            else -> listOf(entry(beer, on, 12.5 + back % 3), entry(beer, on, 14.0 + back % 2), entry(wine, on, 15.5))
        }
    }
    val days = entries.groupBy { it.day }.map { (number, list) -> Day(number).with(DayTotals.of(list)) } +
        listOfNotNull(if (dry) Day(shown.number, isAlcoholFree = true) else null) + Day((shown - 3).number, isAlcoholFree = true)
    return DayState(shown, Ledger(days, clock), settings, entries, clock.start(shown).plusSeconds(3600L * 15))
}

@Preview(showBackground = true, heightDp = 1100)
@Composable
private fun DayPagePreview() {
    GrogLogTheme { DayPage(sampleDayState()) }
}

@Preview(showBackground = true, heightDp = 900, uiMode = Configuration.UI_MODE_NIGHT_YES)
@Composable
private fun DryDayPreview() {
    GrogLogTheme(darkTheme = true) { DayPage(sampleDayState(dry = true)) }
}

@Preview(showBackground = true)
@Composable
private fun TotalsHeaderPreview() {
    GrogLogTheme { TotalsHeader(DayTotals(5.6, 520.0, 21.0, 3), 4.0, "GBP", Modifier.padding(16.dp)) }
}

@Preview(showBackground = true, fontScale = 2f)
@Composable
private fun TotalsHeaderLargePreview() {
    GrogLogTheme { TotalsHeader(DayTotals(5.6, 520.0, 21.0, 3), 4.0, "GBP", Modifier.padding(16.dp)) }
}

@Preview(showBackground = true)
@Composable
private fun BudgetBarPreview() {
    GrogLogTheme {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            BudgetBar(1.2, 4.0)
            BudgetBar(3.4, 4.0)
            BudgetBar(5.6, 4.0)
        }
    }
}
