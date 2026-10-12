package cc.blit.groglog.ui.log

import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import cc.blit.groglog.model.Catalog
import cc.blit.groglog.model.CatalogBrand
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.ServeSize
import cc.blit.groglog.model.Units
import cc.blit.groglog.model.abvText
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.shared.ChipRow
import cc.blit.groglog.ui.shared.MoneyField
import cc.blit.groglog.ui.shared.NumberRow
import cc.blit.groglog.ui.shared.StepperRow
import cc.blit.groglog.ui.shared.TimeRow
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import java.time.Duration
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.roundToInt

/** One of the user's drinks or a catalogue brand, presented the same way. */
data class Choice(
    val name: String,
    val category: DrinkCategory,
    val abv: Double,
    val drink: Drink? = null,
    /** Kept so a catalogue pick can be priced at whichever size is chosen. */
    val brand: CatalogBrand? = null,
) {
    constructor(drink: Drink) : this(drink.name, drink.category, drink.abv, drink = drink)
    constructor(brand: CatalogBrand) : this(brand.name, brand.category, brand.abv, brand = brand)

    /** A brand and the drink adopted from it share a key, so a pick survives being adopted by a star. */
    val key: String get() = Catalog.key(name, category)
}

/**
 * Long-press on a tile: which drink exactly (one of the user's, or a UK brand of the same type), with a star to keep it
 * on the Log grid at this size. The size starts as the tile's and can be overridden from the drink's usual sizes, the
 * strength for this round only, and the round can be several, spread from a chosen time.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LogOptionsSheet(
    base: Serve,
    state: LogState,
    viewModel: LogViewModel,
    onDismiss: () -> Unit,
    onEditDrink: ((Drink) -> Unit)?,
    onLogged: (message: String, count: Int) -> Unit,
) {
    var selected by rememberSaveable { mutableStateOf(Choice(base.drink).key) }
    var size by remember { mutableStateOf(ServeSize(base.vessel, base.volumeMl)) }
    var count by rememberSaveable { mutableIntStateOf(1) }
    var time by remember { mutableStateOf(state.suggestedTime) }
    var search by rememberSaveable { mutableStateOf("") }
    // What this round cost and its strength, when they differ from the usual. Null follows the drink and size, so
    // picking another does not carry over the previous one's figures.
    var price by remember(selected, size) { mutableStateOf<Double?>(null) }
    var abv by remember(selected) { mutableStateOf<Double?>(null) }

    val choices = remember(search, state.drinks) { Picker.choices(base.drink, search, state.drinks) }
    val choice = choices.firstOrNull { it.key == selected } ?: choices[0]
    val usualPrice = viewModel.favourite(choice, size)?.price
        ?: choice.drink?.price(size.vessel, size.ml)
        ?: choice.brand?.let { Catalog.price(it, size.vessel, size.ml, state.currency) }
        ?: 0.0
    val strength = abv ?: choice.abv
    val each = Units.of(size.ml, strength)
    val times = Picker.spreadTimes(time, count, state.day, state.clock)
    val pinned = state.favourites
        .filter { it.favourite.vessel == size.vessel && it.favourite.volumeMl == size.ml }
        .mapTo(HashSet()) { it.drink.id }
    val isToday = state.day == state.ledger.today

    ModalBottomSheet(onDismissRequest = onDismiss) {
        Row(
            Modifier.fillMaxWidth().padding(start = 24.dp, end = 16.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                base.drink.name,
                Modifier.weight(1f).semantics { heading() },
                style = MaterialTheme.typography.titleLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Button(
                onClick = {
                    viewModel.log(choice, size, price ?: usualPrice, times, strength, state.currency)
                    onLogged("${if (count > 1) "$count " else ""}${choice.name} · ${(each * count).unitsText} u", count)
                    onDismiss()
                },
                enabled = Units.isStrength(strength),
            ) {
                Text("Log ${if (count > 1) "$count " else ""}· ${(each * count).unitsText} u", fontWeight = FontWeight.SemiBold)
            }
        }
        LazyColumn(Modifier.imePadding()) {
            item {
                SearchField(search, { search = it }, "Find a drink", Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            }
            item {
                ChipRow(
                    base.drink.sizes(ServeSize(base.vessel, base.volumeMl)),
                    size,
                    { size = it },
                    Modifier.padding(vertical = 8.dp),
                ) { it.label }
            }
            if (base.drink.category != DrinkCategory.UNITS) {
                item { NumberRow("Strength", strength, { abv = it }, "% ABV") }
                item {
                    NumberRow("Units each", (each * 10).roundToInt() / 10.0, { abv = it * 1000 / size.ml }, "u")
                }
            }
            // Under the size, since the size sets the price.
            item { MoneyField("Price", price ?: usualPrice, { price = it }, state.currency) }
            item { StepperRow("How many: $count", count, { count = it }, 1..12) }
            if (isToday) {
                item {
                    val now = Instant.now()
                    val ago = (Duration.between(time, now).toMinutes() / 15.0).roundToInt() * 15
                    ChipRow(listOf(0, 15, 30, 60, 120, 180), ago, { time = now.minusSeconds(it * 60L) }, Modifier.padding(vertical = 4.dp)) {
                        when {
                            it == 0 -> "Now"
                            it < 60 -> "${it}m ago"
                            else -> "${it / 60}h ago"
                        }
                    }
                }
            }
            item { TimeRow(if (count > 1) "First one at" else "At", time, { time = it }, state.clock, state.day) }
            if (count > 1) {
                item {
                    val format = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withZone(state.clock.zone)
                    Text(
                        "Spread from ${format.format(times.first())} to ${format.format(times.last())}.",
                        Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            item {
                Text(
                    "Which one?",
                    Modifier.padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 4.dp).semantics { heading() },
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            items(choices, key = { it.key }) { option ->
                ChoiceRow(
                    choice = option,
                    ml = size.ml,
                    isSelected = option.key == choice.key,
                    isPinned = option.drink?.id in pinned,
                    onSelect = { selected = option.key },
                    onStar = { viewModel.togglePin(option, size, state.currency) },
                    onEdit = option.drink?.let { drink -> onEditDrink?.let { { it(drink) } } },
                )
            }
        }
    }
}

@Composable
private fun ChoiceRow(
    choice: Choice,
    ml: Double,
    isSelected: Boolean,
    isPinned: Boolean,
    onSelect: () -> Unit,
    onStar: () -> Unit,
    onEdit: (() -> Unit)?,
) {
    val haptics = LocalHapticFeedback.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(end = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier
                .weight(1f)
                .semantics { selected = isSelected }
                .combinedClickable(
                    role = Role.RadioButton,
                    onClick = onSelect,
                    onLongClick = onEdit,
                    onLongClickLabel = onEdit?.let { "Edit ${choice.name}" },
                )
                .heightIn(min = 56.dp)
                .padding(start = 16.dp, end = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                Text(choice.name, fontWeight = if (isSelected) FontWeight.SemiBold else null, style = MaterialTheme.typography.bodyLarge)
                Text(
                    "${choice.abv.abvText} · ${Units.of(ml, choice.abv).unitsText} u",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (isSelected) Icon(Icons.Filled.Check, contentDescription = null, tint = GrogColors.grog)
        }
        IconToggleButton(
            checked = isPinned,
            onCheckedChange = {
                haptics.performHapticFeedback(if (it) HapticFeedbackType.ToggleOn else HapticFeedbackType.ToggleOff)
                onStar()
            },
        ) {
            Icon(
                if (isPinned) Icons.Filled.Star else Icons.Outlined.Star,
                contentDescription = if (isPinned) "Remove from Log grid" else "Add to Log grid",
                tint = if (isPinned) GrogColors.grog else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun ChoiceRowPreview() {
    GrogLogTheme {
        Surface {
            Column {
                val drink = Drink(name = "Staropramen", category = DrinkCategory.BEER, abv = 5.0, vessel = cc.blit.groglog.model.Vessel.PINT, volumeMl = 568.0)
                ChoiceRow(Choice(drink), 568.0, isSelected = true, isPinned = true, onSelect = {}, onStar = {}, onEdit = {})
                ChoiceRow(Choice(drink.copy(name = "Beer", abv = 4.0)), 568.0, isSelected = false, isPinned = false, onSelect = {}, onStar = {}, onEdit = null)
            }
        }
    }
}
