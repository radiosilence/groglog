package cc.blit.groglog.ui.setup

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Goal
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Taper
import cc.blit.groglog.model.Units
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import cc.blit.groglog.ui.shared.ChipRow
import cc.blit.groglog.ui.shared.NumberRow
import cc.blit.groglog.ui.shared.Section
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * The goal as a draft, saved on Done. Opens switched on, since opening it is a request for a goal. Amounts are stored
 * per week but typed per day, as people think of a day's drinking whatever the taper's pace.
 */
class GoalViewModel(private val database: AppDatabase, private val prefs: Prefs) : ViewModel() {
    /** The figures as typed, per day. */
    var from by mutableDoubleStateOf(0.0)
    var target by mutableDoubleStateOf(0.0)

    private val _draft = MutableStateFlow<Goal?>(null)
    val draft: StateFlow<Goal?> = _draft.asStateFlow()

    val ledger: StateFlow<Ledger?> = combine(database.queries().days(), prefs.settings) { days, settings -> Ledger(days, settings.clock) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    init {
        viewModelScope.launch {
            var goal = prefs.current().goal
            // A goal that is not running starts now. Its stored date is from whenever it was last on, and a taper counted
            // from then would open weeks into its cuts.
            if (!goal.isEnabled) goal = goal.copy(start = Instant.now())
            goal = goal.copy(isEnabled = true)
            from = goal.baselineWeekly / 7
            target = goal.targetWeekly / 7
            _draft.value = settled(goal)
        }
    }

    /** The draft with the typed figures in it, as Done would save it. A figure that does not parse keeps the last good one. */
    val goal: Goal? get() = _draft.value?.let(::typed)

    private fun typed(draft: Goal) = draft.copy(
        baselineWeekly = from.takeIf { it > 0 }?.times(7) ?: draft.baselineWeekly,
        targetWeekly = target.takeIf { it >= 0 }?.times(7) ?: draft.targetWeekly,
    )

    val canSave: Boolean
        get() = _draft.value != null && from > 0 && target >= 0

    /**
     * Moves the plan back to an offered pace after a change alters which paces are offered. Steps to the quickest still
     * allowed rather than the gentlest, so raising the starting figure costs as little pace as possible. Stepped picks its
     * own pace, so there is nothing to settle.
     */
    fun settle() {
        _draft.update { draft -> draft?.let { settled(typed(it)) } }
    }

    private fun settled(goal: Goal): Goal {
        if (goal.taper == Taper.DYNAMIC) return goal
        val period = Goal.nearestOffered(goal.periodDays, goal.baselineWeekly)
        return goal.copy(periodDays = period, reductionUnits = Goal.nearestOffered(goal.reductionUnits, goal.baselineWeekly, period))
    }

    fun setEnabled(on: Boolean) = _draft.update { it?.copy(isEnabled = on) }

    fun setTaper(taper: Taper) {
        _draft.update { it?.copy(taper = taper) }
        settle()
    }

    fun setPeriod(days: Int) {
        _draft.update { it?.copy(periodDays = days) }
        settle()
    }

    fun setReductionUnits(units: Double) = _draft.update { it?.copy(reductionUnits = units) }

    /** Rounded to a whole unit a day, since a figure such as 30.486 is not useful to plan from. */
    fun useRecent(weekly: Double) {
        from = roundedDaily(weekly) / 7
        settle()
    }

    /** Moves the start to another date, keeping its time of day. */
    fun setStart(date: LocalDate, zone: ZoneId = ZoneId.systemDefault()) = _draft.update {
        it?.copy(start = date.atTime(it.start.atZone(zone).toLocalTime()).atZone(zone).toInstant())
    }

    suspend fun save() {
        goal?.let { prefs.setGoal(it) }
    }

    companion object {
        fun roundedDaily(weekly: Double) = (weekly / 7).roundToInt() * 7.0
    }
}

private fun amount(weekly: Double) = "${(weekly / 7).unitsText} u/day"

private fun oneDecimal(value: Double) = NumberFormat.getNumberInstance().apply { maximumFractionDigits = 1 }.format(value)

private fun periodLabel(days: Int) = Goal.periods.firstOrNull { it.days == days }?.label ?: "$days days"

private fun dateText(instant: Instant, zone: ZoneId) = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(instant.atZone(zone))

private fun dateText(day: DayKey) = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(day.localDate)

/** The Setup row's summary of a goal, in the picker's own words so the two cannot drift apart. */
internal fun goalSummary(goal: Goal, ledger: Ledger): String {
    if (!goal.isEnabled) return "Off"
    // A stepped taper has no period of its own; it is whichever rung the budget has reached today.
    val every = periodLabel(ledger.pace(ledger.today, goal))
    // A linear taper reduces by a fixed number of units, so the row states units rather than a percentage.
    return if (goal.taper == Taper.LINEAR) "−${oneDecimal(goal.reductionUnits)} u/$every" else "−${oneDecimal(goal.reductionPercent)}%/$every"
}

@Composable
internal fun GoalPage(model: GoalViewModel, onClose: () -> Unit, onGuidance: () -> Unit) {
    val draft by model.draft.collectAsStateWithLifecycle()
    val ledger by model.ledger.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    SetupPage(
        title = "Goal",
        navigation = PageNavigation.Close(onClose),
        actions = {
            TextButton(onClick = { scope.launch { model.save(); onClose() } }, enabled = model.canSave) {
                Text("Done", fontWeight = FontWeight.SemiBold)
            }
        },
    ) {
        val goal = draft?.let { model.goal }
        val current = ledger
        if (goal != null && current != null) goalEditor(goal, current, model, onGuidance)
    }
}

internal fun LazyListScope.goalEditor(goal: Goal, ledger: Ledger, model: GoalViewModel, onGuidance: () -> Unit) {
    item(key = "goal") { GoalSection(goal, ledger, model, onGuidance) }

    // Guidance treats a gradual reduction as a decision made for a particular person by a clinician who has assessed
    // them. This screen only records the decision; it cannot say whether a taper is the right approach, and must not
    // read as if it does.
    item(key = "before") {
        Section(title = "Before you start") {
            Text(
                "A taper is suitable only when gradual reduction is already the right approach for you. Your GP or an alcohol service can advise on whether it is, and at what pace. GrogLog helps you follow the plan you agree with them.",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(16.dp),
            )
        }
    }

    // DHSC's UK clinical guidelines for alcohol treatment, chapter 8, step 3. These are the signs the guidance says to
    // stop and get help for, not to taper more slowly through.
    item(key = "emergency") {
        Section(
            title = "Call 999 if you get any of these",
            footer = "These are signs that withdrawal has become serious. They need emergency care, not a slower reduction.",
        ) {
            Column(Modifier.padding(vertical = 8.dp)) {
                for (sign in listOf("A fit or seizure", "Seeing or hearing things that are not there", "Confusion, or being unsteady on your feet")) {
                    Note(sign, Icons.Filled.Warning, GrogColors.over, MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun GoalSection(goal: Goal, ledger: Ledger, model: GoalViewModel, onGuidance: () -> Unit) {
    val zone = ledger.clock.zone
    val recent = ledger.recentWeeklyAverage()
    // Two different figures. Current drinking is what the NICE thresholds apply to. The taper's steps are sized from the
    // baseline it counts down from, which is why editing the baseline changes the options offered.
    val drinking = recent ?: goal.baselineWeekly
    val from = goal.baselineWeekly
    val guideline = "The UK low-risk guideline is ${amount(Units.WEEKLY_GUIDELINE)}."
    val footer = if (!goal.isEnabled) {
        "Choose a rate of reduction to set a daily and weekly budget."
    } else {
        val plan = "${amount(goal.baselineWeekly)} → ${amount(goal.targetWeekly)} from ${dateText(goal.start, zone)}"
        when (goal.taper) {
            Taper.DYNAMIC -> "$plan. Reduces by 10% every four days above 25 u/day, every three days between 15 and 25, and every day below 15. The pace follows the guidance for the current level rather than being chosen. $guideline"
            Taper.PROPORTIONAL -> "$plan, about ${oneDecimal(goal.dailyCut * 100)}% less each day. The cuts become smaller as it goes, so it approaches the target without quite reaching it. $guideline"
            Taper.LINEAR -> "$plan, ${goal.dailyUnitCut.unitsText} u/day less each day. The same amount is removed each time, so it reaches the target on a fixed date. $guideline"
        }
    }
    var pickingDate by rememberSaveable { mutableStateOf(false) }

    Section(title = "Goal", footer = footer) {
        SwitchRow("Cut down", checked = goal.isEnabled, onChange = model::setEnabled)
        if (!goal.isEnabled) return@Section

        FieldLabel("Taper")
        ChipRow(Taper.entries, goal.taper, model::setTaper, label = { it.label })
        Text(
            goal.taper.explanation,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
        val offeredPeriods = Goal.periods(from).map { it.days }
        val offeredUnits = Goal.unitCuts(from, goal.periodDays)
        when (goal.taper) {
            // Stepped has no pace to pick: it takes the one its ladder gives for the current level.
            Taper.DYNAMIC -> SettingsRow(
                title = "Starts at",
                value = "10% every ${periodLabel(Goal.pace(from))}",
                trailingIcon = Icons.Filled.Info,
                onClick = onGuidance,
                onClickLabel = "Where this comes from",
            )
            Taper.LINEAR -> {
                FieldLabel("Cut by")
                ChipRow(Goal.unitCuts, goal.reductionUnits, model::setReductionUnits, isEnabled = { it in offeredUnits }) { "−${oneDecimal(it)} u" }
            }
            Taper.PROPORTIONAL -> Unit
        }
        // The share is fixed at the fastest safe one, so the period alone sets the pace.
        if (goal.taper != Taper.DYNAMIC) {
            FieldLabel(if (goal.taper == Taper.LINEAR) "Every" else "Cut ${Goal.STANDARD_CUT.toInt()}% every")
            ChipRow(Goal.periods.map { it.days }, goal.periodDays, model::setPeriod, isEnabled = { it in offeredPeriods }, label = ::periodLabel)
        }
        // Options grey out while typing, so the narrowing is visible; the selection moves when typing ends.
        NumberRow("From", model.from, { model.from = it }, "u/day", Modifier.padding(top = 8.dp), onEditingEnded = model::settle)
        if (recent != null) {
            val rounded = GoalViewModel.roundedDaily(recent)
            if (abs(rounded - goal.baselineWeekly) > 0.5) {
                TextButton(onClick = { model.useRecent(recent) }, modifier = Modifier.padding(horizontal = 4.dp)) {
                    Text("Use my last 4 weeks (${amount(rounded)})")
                }
            }
        }
        SettingsRow(title = "Starting", value = dateText(goal.start, zone), onClick = { pickingDate = true })
        NumberRow("Down to", model.target, { model.target = it }, "u/day")
        BurndownPreview(goal, ledger)
        ProjectionRow(goal, ledger)
        Warnings(goal, drinking)
    }

    if (pickingDate) {
        val state = rememberDatePickerState(
            initialSelectedDateMillis = goal.start.atZone(zone).toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { pickingDate = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { model.setStart(LocalDate.ofEpochDay(it / 86_400_000), zone) }
                    pickingDate = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { pickingDate = false }) { Text("Cancel") } },
        ) {
            DatePicker(state)
        }
    }
}

@Composable
private fun Warnings(goal: Goal, drinking: Double) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(Modifier.padding(vertical = 4.dp)) {
        if (goal.isFasterThanSafe) {
            Note("This is more than 10% a day, which UK treatment guidance sets as the limit for reducing without medication. A slower taper is safer.", Icons.Filled.Warning, GrogColors.over)
        }
        // The same guidance names 25 units a day as a reason to halve the pace, and NICE gives two thresholds above it
        // where the right response is professional support.
        when {
            drinking >= Goal.INPATIENT_WEEKLY -> Note("Over 30 units a day. At this level NICE recommends inpatient or residential withdrawal rather than reducing alone. Please speak to your GP or an alcohol service before you begin.", Icons.Filled.Warning, GrogColors.over)
            drinking >= Goal.ASSISTED_WITHDRAWAL_WEEKLY -> Note("Over 15 units a day. At this level NICE recommends considering medically assisted withdrawal. Please consider speaking to your GP or an alcohol service about support.", Icons.Filled.Info, secondary)
            drinking > Goal.SLOWER_ABOVE_WEEKLY -> Note("Over 25 units a day, the guidance recommends reducing by no more than 10% every four days, so the faster options are not available.", Icons.Filled.Info, secondary)
        }
        // The pace in units, which the percentage obscures: 10% of 60 is 6. When that is why an option is unavailable,
        // this explains it rather than leaving a gap.
        val opening = goal.openingDrop(goal.baselineWeekly)
        if (opening > 0) Note("That is ${opening.unitsText} u/day less to begin with.", null, secondary)
        // A linear taper's share grows as the budget shrinks, so the warning is a level, worth showing only while the
        // budget is still above the guideline.
        if (goal.sharpensWhileItMatters(goal.baselineWeekly)) {
            Note("The same amount is removed from what remains, so each cut becomes a larger share: below ${goal.sharpensBelow.unitsText} u/day it is more than 10% of what remains each day. Proportional reduces more gently at this point.", Icons.Filled.Warning, GrogColors.over)
        }
    }
}

@Composable
private fun Note(text: String, icon: ImageVector?, color: Color, style: TextStyle = MaterialTheme.typography.bodyMedium) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (icon != null) Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
        Text(text, style = style, color = color)
    }
}

@Composable
private fun FieldLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp),
    )
}

/** Where the taper lands if it is followed. */
@Composable
private fun ProjectionRow(goal: Goal, ledger: Ledger) {
    val projection = ledger.projection(goal)
    Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        projection.target?.let { Figure("${(goal.targetWeekly / 7).unitsText} u/day by", dateText(it), MaterialTheme.colorScheme.onSurface) }
        projection.stoppable?.let { stop ->
            if (stop <= ledger.today) {
                Text("Already low enough to stop", style = MaterialTheme.typography.bodyMedium, color = GrogColors.dry)
            } else {
                Figure("Low enough to stop by", dateText(stop), GrogColors.dry)
            }
        }
    }
}

@Composable
private fun Figure(label: String, value: String, color: Color) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = color, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyMedium, color = color)
    }
}

/** A day of the plan, counted from its start, and the budget on it. */
internal data class BudgetPoint(val step: Int, val units: Double)

/** Where the pace changes, and to what. */
internal data class PaceStep(val step: Int, val pace: Int)

/**
 * The budget for twelve weeks from the start, every day, not every third: the pace changes where the budget crosses a
 * threshold, and sampling past the corner rounds it off into something that looks like a mistake. A day with no budget
 * is left out rather than drawn as nought, which would read as the plan reaching zero.
 */
internal fun burndown(goal: Goal, ledger: Ledger): Pair<List<BudgetPoint>, List<PaceStep>> {
    val start = DayKey.of(goal.start, ledger.clock.zone)
    val points = (0..84).mapNotNull { step -> ledger.dailyBudget(start + step, goal)?.let { BudgetPoint(step, it) } }
    // The first change is a 29% steepening and the second nearly threefold, so left to the curve alone the first one
    // reads as nothing happening.
    val steps = points.zipWithNext().filter { (a, b) -> Goal.pace(a.units * 7) != Goal.pace(b.units * 7) }
        .map { (_, b) -> PaceStep(b.step, Goal.pace(b.units * 7)) }
    return points to steps
}

@Composable
private fun BurndownPreview(goal: Goal, ledger: Ledger) {
    val (points, steps) = remember(goal, ledger) { burndown(goal, ledger) }
    val start = DayKey.of(goal.start, ledger.clock.zone)
    BurndownChart(points, steps, dateText(start), dateText(start + 84))
}

@Composable
private fun BurndownChart(points: List<BudgetPoint>, steps: List<PaceStep>, startLabel: String, endLabel: String) {
    if (points.isEmpty()) return
    val measurer = rememberTextMeasurer()
    val caption = MaterialTheme.typography.labelSmall
    val axis = MaterialTheme.colorScheme.onSurfaceVariant
    val grid = MaterialTheme.colorScheme.outlineVariant
    val dry = GrogColors.dry
    val top = ceil(points.maxOf { it.units }).coerceAtLeast(1.0)
    val summary = "Budget from ${points.first().units.unitsText} to ${points.last().units.unitsText} units a day over twelve weeks" +
        if (steps.isEmpty()) "." else ", quickening ${steps.size} times."
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(150.dp)
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .semantics { contentDescription = summary },
    ) {
        val left = 32.dp.toPx()
        val above = 14.dp.toPx()
        val below = 18.dp.toPx()
        val width = size.width - left
        val height = size.height - above - below
        fun x(step: Int) = left + width * step / 84f
        fun y(units: Double) = above + height * (1 - (units / top).toFloat())

        for (tick in listOf(0.0, top / 2, top)) {
            drawLine(grid, Offset(left, y(tick)), Offset(size.width, y(tick)), 1f)
            val text = measurer.measure(oneDecimal(tick), caption.copy(color = axis))
            drawText(text, topLeft = Offset(left - text.size.width - 6.dp.toPx(), y(tick) - text.size.height / 2))
        }
        val unit = measurer.measure("u/day", caption.copy(color = axis))
        drawText(unit, topLeft = Offset(0f, size.height - unit.size.height))

        val line = Path().apply {
            points.forEachIndexed { index, point -> if (index == 0) moveTo(x(point.step), y(point.units)) else lineTo(x(point.step), y(point.units)) }
        }
        val area = Path().apply {
            addPath(line)
            lineTo(x(points.last().step), y(0.0))
            lineTo(x(points.first().step), y(0.0))
            close()
        }
        drawPath(area, Brush.verticalGradient(listOf(dry.copy(alpha = 0.4f), dry.copy(alpha = 0.05f)), startY = above, endY = above + height))
        // A label that would run into the one before is left off; its rule still marks the change.
        var clear = left
        for (step in steps) {
            drawLine(dry.copy(alpha = 0.35f), Offset(x(step.step), above), Offset(x(step.step), y(0.0)), 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)))
            val label = measurer.measure("10%/${step.pace}d", caption.copy(color = dry))
            val at = (x(step.step) - label.size.width / 2).coerceIn(left, size.width - label.size.width)
            if (at < clear) continue
            drawText(label, topLeft = Offset(at, 0f))
            clear = at + label.size.width + 4.dp.toPx()
        }
        drawPath(line, dry, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))

        val first = measurer.measure(startLabel, caption.copy(color = axis))
        drawText(first, topLeft = Offset(left, size.height - first.size.height))
        val last = measurer.measure(endLabel, caption.copy(color = axis))
        drawText(last, topLeft = Offset(size.width - last.size.width, size.height - last.size.height))
    }
}

/** Where the pace limits come from. Reachable from the pace a stepped taper picks, the figure most likely to be questioned. */
@Composable
internal fun GuidancePage(onClose: () -> Unit) {
    SetupPage(title = "Where this comes from", navigation = PageNavigation.Back(onClose)) {
        item {
            Section(title = "The pace") {
                Paragraph("No more than 10% a day. This limit comes from the DHSC's UK clinical guidelines for alcohol treatment, published in November 2025, the first national guideline to set a figure for reducing without medication.")
                Paragraph("The guideline describes this figure as clinical consensus rather than trial evidence, and assumes a clinician has judged the person suitable and reviews their progress.", secondary = true)
                LinkRow("Read chapter 8, harm reduction", "https://www.gov.uk/guidance/clinical-guidelines-for-alcohol-treatment/8-harm-reduction")
            }
        }
        item {
            Section(title = "Why it starts slower") {
                Paragraph("Over 25 units a day, the same guidance recommends no more than 10% every four days. It says the same for people over 65 or in poor health.")
                Paragraph("The step to every three days between 15 and 25 units is GrogLog's own, not the guideline's. NICE recommends considering assisted withdrawal above 15 units a day, and the 10% limit was not written for unsupervised reduction at that level.", secondary = true)
            }
        }
        item {
            Section(title = "When to ask for help") {
                Paragraph("Over 15 units a day, NICE recommends considering medically assisted withdrawal. Over 30, it recommends inpatient or residential care rather than reducing alone.")
                LinkRow("NICE CG115", "https://www.nice.org.uk/guidance/cg115")
            }
        }
        item {
            Section {
                Paragraph("GrogLog does not provide medical advice. It is intended to help you follow a plan agreed with your GP or alcohol service.")
            }
        }
    }
}

@Composable
private fun Paragraph(text: String, secondary: Boolean = false) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        color = if (secondary) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
    )
}

@Preview(name = "Burndown")
@Composable
private fun BurndownPreviewPreview() {
    val goal = Goal(isEnabled = true, baselineWeekly = 30 * 7.0)
    val ledger = Ledger(emptyList(), DayClock(5))
    GrogLogTheme {
        Surface { BurndownPreview(goal, ledger) }
    }
}
