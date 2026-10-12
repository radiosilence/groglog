package cc.blit.groglog.ui.calendar

import android.content.res.Configuration
import android.text.format.DateFormat
import androidx.activity.compose.PredictiveBackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.DayStatus
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.day.DayPager
import cc.blit.groglog.ui.day.DayViewModel
import cc.blit.groglog.ui.day.sampleDayState
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.time.DayOfWeek
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle as DateTextStyle
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.launch

/**
 * The Calendar tab: every month logged, latest at the bottom. Tapping a day opens it over the calendar; choosing the
 * tab again closes it, or with no day open goes back to this month.
 */
@Composable
fun CalendarScreen(modifier: Modifier = Modifier, reselected: Flow<Unit> = emptyFlow(), onSetGoal: () -> Unit = {}) {
    val model: CalendarViewModel = viewModel(factory = CalendarViewModel.Factory)
    val days: DayViewModel = viewModel(key = "calendar-day", factory = DayViewModel.Factory)
    val state = model.state.collectAsStateWithLifecycle().value
    var open by rememberSaveable { mutableStateOf(false) }
    val list = rememberLazyListState()
    val back = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(reselected) {
        reselected.collect { if (open) open = false else list.animateScrollToItem(0) }
    }
    PredictiveBackHandler(enabled = open) { progress ->
        try {
            progress.collect { back.snapTo(it.progress) }
            open = false
        } catch (cancelled: CancellationException) {
            scope.launch { back.animateTo(0f) }
            throw cancelled
        }
    }

    Box(modifier) {
        if (state != null) {
            CalendarContent(
                state = state,
                list = list,
                onOpen = { day ->
                    days.show(day)
                    scope.launch { back.snapTo(0f) }
                    open = true
                },
                onAlcoholFree = model::setAlcoholFree,
                // Hidden from TalkBack while a day is open over it.
                modifier = if (open) Modifier.clearAndSetSemantics {} else Modifier,
            )
        }
        AnimatedVisibility(open, enter = slideInHorizontally { it }, exit = slideOutHorizontally { it / 3 } + fadeOut()) {
            Surface(
                Modifier
                    .graphicsLayer {
                        // Follows the back gesture as Material's predictive back does: shrinking a little, edging away.
                        val scale = 1 - back.value * 0.1f
                        scaleX = scale
                        scaleY = scale
                        translationX = back.value * 24.dp.toPx()
                        shape = RoundedCornerShape(28.dp * back.value)
                        clip = back.value > 0
                    }
                    // Takes every touch, so none reaches the calendar beneath.
                    .pointerInput(Unit) {},
            ) {
                DayPager(days, onSetGoal, onBack = { open = false })
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CalendarContent(
    state: CalendarState,
    list: LazyListState,
    onOpen: (DayKey) -> Unit,
    onAlcoholFree: (Boolean, DayKey) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scroll = TopAppBarDefaults.pinnedScrollBehavior()
    val differentiate = differentiateWithoutColour()
    val months = state.months.asReversed()
    Scaffold(
        modifier = modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            Column {
                TopAppBar(
                    title = { Text("Calendar") },
                    actions = {
                        val streak = state.ledger.dryStreak()
                        if (streak > 0) {
                            Row(Modifier.padding(end = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Leaf, contentDescription = null, tint = GrogColors.dry, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(6.dp))
                                Text("$streak-day dry streak", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = GrogColors.dry)
                            }
                        }
                    },
                    scrollBehavior = scroll,
                )
                WeekdayHeader(state.ledger.clock.firstWeekday)
            }
        },
    ) { padding ->
        // Laid out from the bottom, so the calendar opens on this month and stays there as months are added.
        LazyColumn(
            state = list,
            reverseLayout = true,
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding() + 8.dp, bottom = padding.calculateBottomPadding() + 16.dp),
            verticalArrangement = Arrangement.spacedBy(32.dp, Alignment.Bottom),
            modifier = Modifier.fillMaxSize(),
        ) {
            items(months, key = { it.number }) { month ->
                MonthGrid(month, state, differentiate, onOpen, onAlcoholFree)
            }
        }
    }
}

/** Seven to a row leaves no room past this text size; TalkBack reads each day in full. */
@Composable
private fun CappedText(content: @Composable () -> Unit) {
    val density = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(density.density, density.fontScale.coerceAtMost(1.3f)), content = content)
}

@Composable
private fun WeekdayHeader(firstWeekday: Int) {
    val locale = Locale.getDefault()
    CappedText {
        Row(
            Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceContainer)
                .padding(horizontal = 16.dp, vertical = 8.dp)
                .clearAndSetSemantics {},
        ) {
            for (index in 0 until 7) {
                // `firstWeekday` counts from Sunday as 1; DayOfWeek from Monday.
                val weekday = DayOfWeek.of((firstWeekday + index + 5) % 7 + 1)
                Text(
                    weekday.getDisplayName(DateTextStyle.NARROW_STANDALONE, locale),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun MonthGrid(
    month: DayKey,
    state: CalendarState,
    differentiate: Boolean,
    onOpen: (DayKey) -> Unit,
    onAlcoholFree: (Boolean, DayKey) -> Unit,
) {
    val locale = Locale.getDefault()
    val cells = state.cells(month)
    val units = cells.sumOf { it.units }
    val dry = cells.count { it.status == DayStatus.ALCOHOL_FREE }
    val title = month.localDate.format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "MMMMy"), locale))

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() })
            Spacer(Modifier.weight(1f))
            Text(
                "${units.unitsText} u · $dry dry",
                style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.semantics { contentDescription = "${units.unitsText} units, $dry alcohol-free" },
            )
        }
        CappedText {
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                for (week in (List(state.leadingBlanks(month)) { null } + cells).chunked(7)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        for (index in 0 until 7) {
                            val cell = week.getOrNull(index)
                            if (cell == null) {
                                Spacer(Modifier.weight(1f))
                            } else {
                                DayCell(cell, differentiate, onOpen, onAlcoholFree, Modifier.weight(1f))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DayCell(
    cell: DayCellState,
    differentiate: Boolean,
    onOpen: (DayKey) -> Unit,
    onAlcoholFree: (Boolean, DayKey) -> Unit,
    modifier: Modifier = Modifier,
) {
    val status = cell.status
    val haptics = LocalHapticFeedback.current
    var menu by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(10.dp)
    val marked = status == DayStatus.DRANK || status == DayStatus.ALCOHOL_FREE
    val fill = when (status) {
        DayStatus.DRANK -> GrogColors.heat(cell.units, cell.budget)
        DayStatus.ALCOHOL_FREE -> GrogColors.dry
        else -> null
    }
    val ink = if (marked) Color.White else MaterialTheme.colorScheme.onSurface
    val dashed = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
    val outline = MaterialTheme.colorScheme.outlineVariant
    // A day with drinks has nothing to offer on a long press; a dry day can be unmarked, any other marked dry.
    val dryMark: Boolean? = when (status) {
        DayStatus.ALCOHOL_FREE -> false
        DayStatus.TODAY, DayStatus.UNLOGGED, DayStatus.UNTRACKED -> true
        else -> null
    }
    val dryLabel = if (dryMark == true) "Alcohol-free" else "Not alcohol-free"
    val locale = Locale.getDefault()
    val label = cell.day.localDate.format(DateTimeFormatter.ofPattern(DateFormat.getBestDateTimePattern(locale, "EEEEdMMMM"), locale))

    Box(
        modifier
            .height(56.dp)
            .alpha(if (status == DayStatus.FUTURE) 0.5f else 1f)
            .then(if (fill != null) Modifier.background(Brush.verticalGradient(listOf(lerp(fill, Color.White, 0.12f), fill)), shape) else Modifier)
            .then(
                when {
                    cell.isToday -> Modifier.border(2.5.dp, GrogColors.grog, shape)
                    status == DayStatus.FUTURE || status == DayStatus.UNTRACKED -> Modifier.border(1.dp, outline, shape)
                    status == DayStatus.UNLOGGED -> Modifier.drawBehind {
                        val inset = 0.5.dp.toPx()
                        drawRoundRect(
                            dashed,
                            topLeft = Offset(inset, inset),
                            size = Size(size.width - 2 * inset, size.height - 2 * inset),
                            cornerRadius = CornerRadius(10.dp.toPx()),
                            style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 3.dp.toPx()))),
                        )
                    }
                    else -> Modifier
                },
            )
            .then(
                if (status == DayStatus.FUTURE) {
                    Modifier
                } else {
                    Modifier.combinedClickable(
                        onClickLabel = "Open",
                        onLongClickLabel = dryMark?.let { "Mark" },
                        onLongClick = dryMark?.let {
                            {
                                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                menu = true
                            }
                        },
                        onClick = { onOpen(cell.day) },
                    )
                },
            )
            .semantics(mergeDescendants = true) {
                contentDescription = label
                stateDescription = cell.spoken
                if (dryMark != null) {
                    customActions = listOf(
                        CustomAccessibilityAction(dryLabel) {
                            onAlcoholFree(dryMark, cell.day)
                            true
                        },
                    )
                }
            }
            .padding(5.dp),
    ) {
        Box(Modifier.fillMaxSize().clearAndSetSemantics {}) {
            Text(
                "${cell.day.components.day}",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.SemiBold,
                color = ink.copy(alpha = if (marked) 0.85f else 0.6f),
                modifier = Modifier.align(Alignment.TopStart),
            )
            if (differentiate && status == DayStatus.DRANK) {
                cell.heat.mark?.let {
                    Text(it, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Black, color = ink, modifier = Modifier.align(Alignment.TopEnd))
                }
            }
            Box(Modifier.align(Alignment.Center).padding(top = 8.dp)) {
                when (status) {
                    DayStatus.DRANK -> BasicText(
                        cell.units.unitsText,
                        style = TextStyle(color = ink, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum"),
                        maxLines = 1,
                        autoSize = TextAutoSize.StepBased(minFontSize = 11.sp, maxFontSize = 16.sp),
                    )
                    DayStatus.ALCOHOL_FREE -> Icon(Leaf, contentDescription = null, tint = ink, modifier = Modifier.size(18.dp))
                    DayStatus.UNLOGGED -> Text("?", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.35f))
                    else -> Unit
                }
            }
        }
        if (dryMark != null) {
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(dryLabel) },
                    leadingIcon = { Icon(Leaf, contentDescription = null, tint = if (dryMark) GrogColors.dry else MaterialTheme.colorScheme.onSurfaceVariant) },
                    onClick = {
                        menu = false
                        if (dryMark) haptics.performHapticFeedback(HapticFeedbackType.Confirm)
                        onAlcoholFree(dryMark, cell.day)
                    },
                )
            }
        }
    }
}

internal fun sampleCalendarState(): CalendarState {
    val day = sampleDayState()
    return CalendarState(day.ledger, day.settings.goal)
}

@Preview(showBackground = true, heightDp = 900)
@Composable
private fun CalendarPreview() {
    GrogLogTheme { CalendarContent(sampleCalendarState(), rememberLazyListState(), {}, { _, _ -> }) }
}

@Preview(showBackground = true, heightDp = 900, uiMode = Configuration.UI_MODE_NIGHT_YES)
@Composable
private fun CalendarDarkPreview() {
    GrogLogTheme(darkTheme = true) { CalendarContent(sampleCalendarState(), rememberLazyListState(), {}, { _, _ -> }) }
}

@Preview(showBackground = true, widthDp = 380)
@Composable
private fun DayCellPreview() {
    val today = sampleDayState().day
    val cells = listOf(
        DayCellState(today - 5, DayStatus.DRANK, 2.8, 4.0, false),
        DayCellState(today - 4, DayStatus.DRANK, 5.1, 4.0, false),
        DayCellState(today - 3, DayStatus.DRANK, 8.4, 4.0, false),
        DayCellState(today - 2, DayStatus.ALCOHOL_FREE, 0.0, 4.0, false),
        DayCellState(today - 1, DayStatus.UNLOGGED, 0.0, 4.0, false),
        DayCellState(today, DayStatus.TODAY, 0.0, 4.0, true),
        DayCellState(today + 1, DayStatus.FUTURE, 0.0, 4.0, false),
    )
    GrogLogTheme {
        Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            for (cell in cells) DayCell(cell, differentiate = true, onOpen = {}, onAlcoholFree = { _, _ -> }, modifier = Modifier.weight(1f))
        }
    }
}
