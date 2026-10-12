package cc.blit.groglog.ui.setup

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.setTextAndPlaceCursorAtEnd
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import cc.blit.groglog.data.AppDatabase
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.model.Catalog
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.ServeSize
import cc.blit.groglog.model.Units
import cc.blit.groglog.model.Vessel
import cc.blit.groglog.ui.shared.ChipRow
import cc.blit.groglog.ui.textField
import cc.blit.groglog.ui.shared.MoneyField
import cc.blit.groglog.ui.shared.NumberRow
import cc.blit.groglog.ui.shared.decimalText
import cc.blit.groglog.ui.shared.moneyDigits
import cc.blit.groglog.ui.shared.moneyValue
import cc.blit.groglog.ui.shared.parseDecimal
import cc.blit.groglog.model.abvText
import cc.blit.groglog.model.kcalText
import cc.blit.groglog.model.unitsText
import cc.blit.groglog.ui.shared.DrinkGlyph
import cc.blit.groglog.ui.theme.GrogColors
import cc.blit.groglog.ui.theme.GrogLogTheme
import cc.blit.groglog.ui.shared.Section
import java.util.UUID
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Every drink, split as the list shows it. */
data class DrinkGroups(val yours: List<Drink>, val fromCatalogue: List<Drink>, val generic: List<Drink>)

class DrinksViewModel(private val database: AppDatabase, private val prefs: Prefs) : ViewModel() {
    /**
     * Logging a brand copies it in, so untouched catalogue copies get their own heading; listed under Yours they would
     * bury the few drinks the user created or changed.
     */
    val drinks: StateFlow<DrinkGroups?> = database.queries().drinks().map { drinks ->
        val (generic, mine) = drinks.partition { it.isGeneric }
        val (adopted, customised) = mine.partition { Catalog.holds(it.name, it.category, it.abv) }
        DrinkGroups(customised, adopted, generic)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    fun setHidden(drink: Drink, hidden: Boolean) {
        viewModelScope.launch { Logbook(database, prefs.current().clock).save(drink.copy(isHidden = hidden)) }
    }
}

/**
 * Creates or edits a drink: what it is (name, type, strength), plus its usual size and price. Sizes come from the type,
 * so a beer is offered pints and cans, never a wine glass. Edits a draft, written on save; a changed name or strength
 * carries to everything logged as the drink.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class DrinkEditorViewModel(
    private val database: AppDatabase,
    private val prefs: Prefs,
    private val id: UUID?,
    private val startingName: String = "",
    private val saved: SavedStateHandle? = null,
) : ViewModel() {
    /** Whether this is a draft brought back after the page left the screen or the process stopped. */
    private val restored = saved?.contains(CATEGORY) == true

    val name = saved.textField("name", viewModelScope)
    val strength = saved.textField("strength", viewModelScope, decimalText(DrinkCategory.BEER.defaultABV))
    val price = saved.textField("price", viewModelScope)

    /** The parts of the draft that are not typed. Null until the drink has loaded. */
    private val _draft = MutableStateFlow<Drink?>(null)
    val draft: StateFlow<Drink?> = _draft.asStateFlow()

    var original: Drink? = null
        private set

    var currency: String = "GBP"
        private set

    val timesLogged: StateFlow<Int> = (id?.let { database.queries().pourCount(it) } ?: flowOf(0))
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0)

    init {
        viewModelScope.launch {
            currency = prefs.current().currency
            val drink = id?.let { database.rows().drink(it) }
            original = drink
            val start = drink ?: Drink(name = startingName, category = DrinkCategory.BEER, abv = DrinkCategory.BEER.defaultABV, vessel = Vessel.PINT, volumeMl = 568.0)
            if (restored) {
                _draft.value = start.copy(
                    category = DrinkCategory.valueOf(saved!![CATEGORY]!!),
                    vessel = Vessel.valueOf(saved[VESSEL]!!),
                    volumeMl = saved[VOLUME]!!,
                    isHidden = saved[HIDDEN]!!,
                )
            } else {
                name.setTextAndPlaceCursorAtEnd(start.name)
                strength.setTextAndPlaceCursorAtEnd(decimalText(start.abv))
                price.setTextAndPlaceCursorAtEnd(moneyDigits(start.price, currency))
                _draft.value = start
            }
            // The untyped parts of the draft, kept as they change.
            val saved = saved ?: return@launch
            _draft.collect { draft ->
                draft ?: return@collect
                saved[CATEGORY] = draft.category.name
                saved[VESSEL] = draft.vessel.name
                saved[VOLUME] = draft.volumeMl
                saved[HIDDEN] = draft.isHidden
            }
        }
    }

    val isNew: Boolean get() = id == null

    /** The typed strength, if it is one a drink can have. Impossible figures are refused rather than saved. */
    val abv: Double? get() = parseDecimal(strength.text)?.takeIf(Units::isStrength)

    val canSave: Boolean get() = name.text.isNotBlank() && abv != null && _draft.value != null

    /** Changing the type resets the size and, for a new drink, the strength to that type's usual. */
    fun setCategory(category: DrinkCategory) {
        val size = category.serves[0]
        _draft.update { it?.copy(category = category, vessel = size.vessel, volumeMl = size.ml) }
        if (isNew) strength.setTextAndPlaceCursorAtEnd(decimalText(category.defaultABV))
    }

    fun setSize(size: ServeSize) {
        _draft.update { it?.copy(vessel = size.vessel, volumeMl = size.ml) }
    }

    fun setHidden(hidden: Boolean) {
        _draft.update { it?.copy(isHidden = hidden) }
    }

    /** The draft as it would be saved, or null while it cannot be. */
    fun edited(): Drink? {
        val draft = _draft.value ?: return null
        val abv = abv ?: return null
        val name = name.text.trim().toString().ifEmpty { return null }
        return draft.copy(name = name, abv = abv, price = moneyValue(price.text, currency))
    }

    suspend fun save(): Boolean {
        val drink = edited() ?: return false
        val logbook = Logbook(database, prefs.current().clock)
        if (original == null) logbook.add(drink) else logbook.save(drink)
        return true
    }

    /** Saves the draft as a drink of its own, leaving this one and everything logged as it unchanged. */
    suspend fun saveAsNew(): Boolean {
        val drink = edited() ?: return false
        Logbook(database, prefs.current().clock).add(drink.copy(id = UUID.randomUUID(), isGeneric = false))
        return true
    }

    suspend fun delete() {
        original?.let { Logbook(database, prefs.current().clock).delete(it) }
    }

    private companion object {
        const val CATEGORY = "category"
        const val VESSEL = "vessel"
        const val VOLUME = "volumeMl"
        const val HIDDEN = "isHidden"
    }
}

internal fun LazyListScope.drinksList(groups: DrinkGroups, onEdit: (Drink) -> Unit, onHide: (Drink, Boolean) -> Unit) {
    fun section(title: String, drinks: List<Drink>, footer: String? = null) {
        if (drinks.isEmpty()) return
        item(key = title) {
            Section(title = title, footer = footer) {
                drinks.forEachIndexed { index, drink ->
                    key(drink.id) {
                        if (index > 0) HorizontalDivider(Modifier.padding(start = 72.dp), color = MaterialTheme.colorScheme.surface)
                        DrinkRow(drink, onClick = { onEdit(drink) }, onHide = { onHide(drink, it) })
                    }
                }
            }
        }
    }
    section("Yours", groups.yours)
    section(
        "From the catalogue",
        groups.fromCatalogue,
        "Brands copied in as you logged them, exactly as the catalogue lists them. Changing one, such as its strength, moves it up to Yours.",
    )
    section("Generic", groups.generic)
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DrinkRow(drink: Drink, onClick: () -> Unit, onHide: (Boolean) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val toggle = if (drink.isHidden) "Show in pickers" else "Hide from pickers"
    Box {
        ListItem(
            headlineContent = { Text(drink.name) },
            supportingContent = {
                Text(if (drink.category == DrinkCategory.UNITS) "any amount" else "${drink.category.label} · ${drink.abv.abvText}")
            },
            leadingContent = { DrinkGlyph(drink.category, drink.vessel, Modifier.size(40.dp), drink.volumeMl) },
            trailingContent = if (drink.isHidden) ({ Text("Hidden", style = MaterialTheme.typography.labelMedium) }) else null,
            colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
            modifier = Modifier
                .combinedClickable(onClick = onClick, onLongClick = { menu = true }, onLongClickLabel = toggle, role = Role.Button)
                .semantics {
                    if (drink.isHidden) stateDescription = "Hidden"
                    customActions = listOf(CustomAccessibilityAction(toggle) { onHide(!drink.isHidden); true })
                }
                .alpha(if (drink.isHidden) 0.55f else 1f),
        )
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(toggle) }, onClick = {
                menu = false
                onHide(!drink.isHidden)
            })
        }
    }
}

@Composable
internal fun DrinksPage(groups: DrinkGroups?, onBack: () -> Unit, onNew: () -> Unit, onEdit: (Drink) -> Unit, onHide: (Drink, Boolean) -> Unit) {
    SetupPage(
        title = "Drinks",
        navigation = PageNavigation.Back(onBack),
        actions = {
            IconButton(onClick = onNew) { Icon(Icons.Filled.Add, contentDescription = "New drink") }
        },
    ) {
        if (groups != null) drinksList(groups, onEdit, onHide)
    }
}

/** The editor's form, given the draft's untyped parts; the typed ones live in the view model's field states. */
@Composable
internal fun DrinkEditorPage(
    model: DrinkEditorViewModel,
    timesLogged: Int,
    onClose: () -> Unit,
) {
    val draft = model.draft.collectAsStateWithLifecycle().value ?: return
    val scope = rememberCoroutineScope()
    val original = model.original
    val confirm = if (model.isNew) "Add" else "Save"
    SetupPage(
        title = if (model.isNew) "New drink" else model.name.text.toString().ifBlank { original?.name ?: "" },
        navigation = PageNavigation.Close(onClose),
        actions = {
            TextButton(onClick = { scope.launch { if (model.save()) onClose() } }, enabled = model.canSave) {
                Text(confirm, fontWeight = FontWeight.SemiBold)
            }
        },
    ) {
        item { DrinkHeader(draft, model.abv) }
        item {
            Section {
                OutlinedTextField(
                    state = model.name,
                    label = { Text("Name") },
                    placeholder = { Text("e.g. Staropramen") },
                    lineLimits = TextFieldLineLimits.SingleLine,
                    modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 4.dp),
                )
                if (original?.isGeneric != true) {
                    ChipRow(
                        options = DrinkCategory.entries.filter { it != DrinkCategory.UNITS },
                        selected = draft.category,
                        onSelect = model::setCategory,
                        label = { it.label },
                    )
                }
                NumberRow(
                    "Strength",
                    model.strength,
                    "% ABV",
                    Modifier.padding(bottom = 8.dp),
                    error = if (model.abv == null) "Enter a strength above 0% and at most 100%." else null,
                )
            }
        }
        if (draft.category != DrinkCategory.UNITS) {
            item {
                Section(title = "Usual size", footer = "The size it is offered in first. Long-press a tile to log it in another size.") {
                    ChipRow(
                        options = draft.sizes(ServeSize(draft.vessel, draft.volumeMl)),
                        selected = ServeSize(draft.vessel, draft.volumeMl),
                        onSelect = model::setSize,
                        label = { it.label },
                        modifier = Modifier.padding(top = 8.dp),
                    )
                    MoneyField("Price", model.price, model.currency, Modifier.padding(bottom = 8.dp))
                }
            }
        }
        if (original != null && !original.isGeneric) {
            item {
                Section(
                    footer = "Saving updates everything logged as this drink. If the drink itself changed, save it as a new one and the old entries stay as they were.",
                ) {
                    SettingsRow(
                        title = "Save as new drink",
                        icon = Icons.Filled.Add,
                        enabled = model.canSave,
                        onClick = { scope.launch { if (model.saveAsNew()) onClose() } },
                    )
                    SwitchRow("Show in pickers", checked = !draft.isHidden, onChange = { model.setHidden(!it) })
                    if (timesLogged == 0) {
                        SettingsRow(
                            title = "Delete drink",
                            icon = Icons.Filled.Delete,
                            destructive = true,
                            onClick = { scope.launch { model.delete(); onClose() } },
                        )
                    }
                }
            }
        }
    }
}

/** The drink as drawn on the grid, with what one of it comes to. */
@Composable
private fun DrinkHeader(draft: Drink, abv: Double?) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        DrinkGlyph(draft.category, draft.vessel, Modifier.size(96.dp), draft.volumeMl)
        val figures = abv?.let {
            "${Units.of(draft.volumeMl, it).unitsText} u · ${Units.kcal(draft.volumeMl, it, draft.category).kcalText} kcal"
        } ?: "–"
        AnimatedContent(figures, label = "figures") {
            Text(it, style = MaterialTheme.typography.titleMedium, color = GrogColors.grog, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Preview(name = "Drinks")
@Composable
private fun DrinksPreview() {
    val beer = Drink(name = "Beer", category = DrinkCategory.BEER, abv = 4.0, vessel = Vessel.PINT, volumeMl = 568.0, isGeneric = true)
    val wine = Drink(name = "Red wine", category = DrinkCategory.RED_WINE, abv = 12.0, vessel = Vessel.WINE_GLASS, volumeMl = 175.0, isGeneric = true)
    val hepcat = Drink(name = "Gipsy Hill Hepcat", category = DrinkCategory.BEER, abv = 4.6, vessel = Vessel.PINT, volumeMl = 568.0)
    val old = Drink(name = "Old Rosie", category = DrinkCategory.CIDER, abv = 7.3, vessel = Vessel.PINT, volumeMl = 568.0, isHidden = true)
    GrogLogTheme {
        Surface {
            DrinksPage(DrinkGroups(listOf(hepcat, old), emptyList(), listOf(beer, wine)), {}, {}, {}, { _, _ -> })
        }
    }
}
