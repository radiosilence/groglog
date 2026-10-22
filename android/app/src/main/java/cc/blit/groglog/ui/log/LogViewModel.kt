package cc.blit.groglog.ui.log

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cc.blit.groglog.AppContainer
import cc.blit.groglog.core.CorePicker
import cc.blit.groglog.core.PickerPour
import cc.blit.groglog.data.Logbook
import cc.blit.groglog.data.Prefs
import cc.blit.groglog.data.Queries
import cc.blit.groglog.model.Catalog
import cc.blit.groglog.model.CatalogItem
import cc.blit.groglog.model.DayClock
import cc.blit.groglog.model.DayKey
import cc.blit.groglog.model.Drink
import cc.blit.groglog.model.DrinkCategory
import cc.blit.groglog.model.Entry
import cc.blit.groglog.model.Favourite
import cc.blit.groglog.model.Generics
import cc.blit.groglog.model.FavouriteItem
import cc.blit.groglog.model.HourCounter
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Pour
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.ServeSize
import cc.blit.groglog.model.searchFolded
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.lifecycle.SavedStateHandle
import cc.blit.groglog.data.Serves

/** What the picker draws for one day. Everything past the inputs is derived. */
data class LogState(
    val day: DayKey,
    val ledger: Ledger,
    val currency: String,
    val query: String,
    val favourites: List<FavouriteItem>,
    val drinks: List<Drink>,
    /** The day's entries, oldest first. */
    val pours: List<Entry>,
    val tiles: List<Serve>,
    val catalog: List<CatalogItem>,
    /** How many of each serve are logged on the day, by `Serve.id`. */
    val counts: Map<String, Int>,
    /** Bumped per tile each time it is logged, to play the pour. */
    val pulses: Map<String, Int>,
) {
    val clock: DayClock get() = ledger.clock

    /** When the next drink is put if no time is chosen: now for today, otherwise just after the day's last. */
    val suggestedTime: Instant get() = clock.suggestedTime(day, pours.lastOrNull()?.timestamp)
}

private data class Content(val day: DayKey, val favourites: List<FavouriteItem>, val drinks: List<Drink>, val pours: List<Entry>)

/**
 * The Log picker for one day: today's when `fixedDay` is null, following the clock past the day's end, or a past day
 * being backfilled.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class LogViewModel(
    private val queries: Queries,
    prefs: Prefs,
    private val logbook: suspend () -> Logbook,
    fixedDay: DayKey? = null,
    private val saved: SavedStateHandle? = null,
) : ViewModel() {
    constructor(container: AppContainer, fixedDay: DayKey? = null, saved: SavedStateHandle? = null) :
        this(container.queries, container.prefs, container::logbook, fixedDay, saved)

    private var searchText by mutableStateOf(saved?.get<String>(SEARCH) ?: "")

    /** Kept with the entry, so the grid a sheet was opened from is the one it comes back to. */
    var search: String
        get() = searchText
        set(value) {
            searchText = value
            saved?.set(SEARCH, value)
        }

    private val appeared = MutableStateFlow(0)

    /**
     * The day's drinks as of when the screen appeared, so tapping a tile does not reorder the grid while it is in use.
     * Deliberate picks (the options sheet, a catalogue result) move to the front straight away.
     */
    private val recency = MutableStateFlow<Map<String, Instant>?>(null)
    private val pulses = MutableStateFlow(emptyMap<String, Int>())

    private val settings = prefs.settings

    /** Today moves on at the day's end even while the screen stays open and nothing is logged. */
    private val day: Flow<DayKey> =
        if (fixedDay != null) {
            flowOf(fixedDay)
        } else {
            combine(settings, appeared) { it, _ -> it.clock }.flatMapLatest { days(it) }.distinctUntilChanged()
        }

    private val content: StateFlow<Content?> =
        combine(queries.favourites(), queries.drinks(), day.flatMapLatest { day -> queries.entries(day..day).map { day to it } }) { favourites, drinks, (day, pours) ->
            Content(day, favourites, drinks, pours)
        }.stateIn(viewModelScope, SharingStarted.Eagerly, null)

    /**
     * The whole history scored for the moment a drink would be logged, taken when the screen appears or the day changes,
     * for the same reason. A newer scoring cancels one still running, so the last to start is the one kept.
     */
    private val usual: StateFlow<Usual?> =
        combine(content.filterNotNull().map { it.day }.distinctUntilChanged(), appeared) { day, _ -> day }
            .mapLatest { day -> content.value?.takeIf { it.day == day }?.let { rank(it) } }
            .filterNotNull()
            .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    private val ledger = combine(queries.days(), settings) { days, settings -> Ledger(days, settings.clock) to settings.currency }

    /** Waits for the first scoring, so no tile is drawn where the usual drinks would then push it down. */
    val state: StateFlow<LogState?> =
        combine(content.filterNotNull(), ledger, snapshotFlow { search }, combine(recency, usual.filterNotNull(), ::Pair), pulses) { content, (ledger, currency), query, (frozen, usual), pulses ->
            val order = frozen ?: Picker.recency(content.pours)
            LogState(
                day = content.day,
                ledger = ledger,
                currency = currency,
                query = query,
                favourites = content.favourites,
                drinks = content.drinks,
                pours = content.pours,
                tiles = Picker.tiles(query, content.favourites, content.drinks, content.pours, order, usual),
                catalog = Picker.catalogMatches(query, content.drinks),
                counts = content.pours.groupingBy { it.serveKey }.eachCount(),
                pulses = pulses,
            )
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    init {
        viewModelScope.launch {
            val first = content.filterNotNull().first()
            recency.compareAndSet(null, Picker.recency(first.pours))
        }
    }

    /** The screen came into view: re-anchor today, and take the order the grid will hold while it is used. */
    fun appeared() {
        appeared.update { it + 1 }
        content.value?.let { recency.value = Picker.recency(it.pours) }
    }

    /**
     * Scores every serve ever logged for when the next drink would go: now for today, or that evening on a past day. The
     * history grows without bound, so it is scored off the main thread.
     */
    private suspend fun rank(content: Content): Usual {
        val clock = settings.first().clock
        val at = clock.suggestedTime(content.day, content.pours.lastOrNull()?.timestamp)
        val history = queries.history()
        return withContext(Dispatchers.Default) { Usual.of(history, content.drinks, clock, content.day, at) }
    }

    /**
     * Logs one now, or just after the day's last drink on a past day. Each way of logging hands `onLogged` the entries it
     * wrote, so an undo offered for them takes back those and nothing else, or null when the write failed.
     */
    fun log(serve: Serve, onLogged: (List<Pour>?) -> Unit = {}) {
        val state = state.value ?: return
        // A search result is a deliberate pick, so it comes to the front rather than joining the end once the search
        // is cleared.
        if (search.isNotBlank()) bringForward(serve.id)
        pulse(serve.id)
        val time = state.suggestedTime
        viewModelScope.launch { onLogged(logbook().log(serve, listOf(time))) }
    }

    /** A round from the options sheet: several at chosen times, at a strength of its own, brought to the front. */
    fun log(serve: Serve, times: List<Instant>, abv: Double?, onLogged: (List<Pour>?) -> Unit = {}) {
        bringForward(serve.id)
        pulse(serve.id)
        viewModelScope.launch { onLogged(logbook().log(serve, times, abv)) }
    }

    /** A catalogue pick becomes one of the user's drinks, logged at this size and brought to the front. */
    fun adopt(item: CatalogItem, currency: String, onLogged: (List<Pour>?) -> Unit = {}) {
        search = ""
        viewModelScope.launch {
            val logbook = logbook()
            val price = item.price(currency)
            val drink = logbook.drink(item.name, item.category, item.abv, item.vessel, item.volumeMl, price) ?: return@launch
            val serve = Serve(drink, item.vessel, item.volumeMl, price)
            val time = state.value?.suggestedTime ?: Instant.now()
            bringForward(serve.id)
            pulse(serve.id)
            onLogged(logbook.log(serve, listOf(time)))
        }
    }

    fun logUnits(units: Double, time: Instant, onLogged: (List<Pour>?) -> Unit = {}) {
        viewModelScope.launch { onLogged(logbook().logUnits(units, time)) }
    }

    /** Takes back the drink last logged on the day. */
    fun undo() {
        val day = state.value?.day ?: return
        viewModelScope.launch { logbook().undo(day) }
    }

    /** Takes back exactly these entries, as logged together. */
    fun undo(pours: List<Pour>) {
        viewModelScope.launch { logbook().delete(pours) }
    }

    fun setAlcoholFree(dry: Boolean) {
        val day = state.value?.day ?: return
        viewModelScope.launch { logbook().setAlcoholFree(dry, day) }
    }

    /** Stars a choice onto the Log grid at this size, or takes it off. A catalogue brand is adopted first. */
    fun togglePin(choice: Choice, size: ServeSize, currency: String) {
        val pinned = favourite(choice, size)
        viewModelScope.launch {
            val logbook = logbook()
            if (pinned != null) {
                logbook.unpin(pinned)
            } else {
                resolve(logbook, choice, size, currency)?.let { logbook.pin(Serve(it, size.vessel, size.ml)) }
            }
        }
    }

    /** The favourite for this choice at this size, if it is on the grid. */
    fun favourite(choice: Choice, size: ServeSize): Favourite? {
        val drink = choice.drink ?: return null
        return state.value?.favourites?.firstOrNull {
            it.drink.id == drink.id && it.favourite.vessel == size.vessel && it.favourite.volumeMl == size.ml
        }?.favourite
    }

    /** Logs a round of a choice, adopting a catalogue brand first. */
    fun log(choice: Choice, size: ServeSize, price: Double, times: List<Instant>, abv: Double, currency: String, onLogged: (List<Pour>?) -> Unit = {}) {
        viewModelScope.launch {
            val drink = resolve(logbook(), choice, size, currency) ?: return@launch
            log(Serve(drink, size.vessel, size.ml, price), times, abv, onLogged)
        }
    }

    private suspend fun resolve(logbook: Logbook, choice: Choice, size: ServeSize, currency: String): Drink? {
        choice.drink?.let { return it }
        val price = choice.brand?.let { Catalog.price(it, size.vessel, size.ml, currency) } ?: 0.0
        return logbook.drink(choice.name, choice.category, choice.abv, size.vessel, size.ml, price)
    }

    private fun bringForward(id: String) {
        recency.update { (it ?: emptyMap()) + (id to Instant.now()) }
    }

    private fun pulse(id: String) {
        pulses.update { it + (id to (it[id] ?: 0) + 1) }
    }

    /** A tile by `Serve.id`: from the grid as it stands, or from the database when the grid has yet to load. */
    suspend fun serve(id: String): Serve? = state.value?.tiles?.firstOrNull { it.id == id } ?: Serves.matching(id, logbook().database)

    companion object {
        private const val SEARCH = "search"

        /** The clock's today, and again each time a day ends. */
        internal fun days(clock: DayClock, now: () -> Instant = Instant::now): Flow<DayKey> = flow {
            while (true) {
                val today = clock.day(now())
                emit(today)
                delay(Duration.between(now(), clock.end(today)).toMillis().coerceAtLeast(0) + 1)
            }
        }
    }

}

/**
 * The whole history scored for one moment by the shared core, with a pour of each serve it found usual then. Tiles are
 * built from the pours against the drinks as they are when drawn, so an edit or a hide shows at once.
 */
class Usual(val picker: CorePicker, val pours: Map<String, Pour>) {
    companion object {
        val none by lazy { Usual(CorePicker(emptyList(), 0, 0.0), emptyMap()) }

        /** Hidden drinks are left out, so they never come back as usual. */
        fun of(history: List<Pour>, drinks: List<Drink>, clock: DayClock, day: DayKey, at: Instant): Usual {
            val hidden = drinks.filter { it.isHidden }.mapTo(HashSet()) { it.id }
            val hours = HourCounter(clock)
            val pours = HashMap<String, Pour>()
            val rows = history.mapNotNull { pour ->
                if (pour.drinkId in hidden) return@mapNotNull null
                val key = Serve.key(pour.drinkId, pour.vessel, pour.volumeMl)
                pours.putIfAbsent(key, pour)
                PickerPour(key, pour.day.toLong(), hours.hours(pour.timestamp, pour.dayKey))
            }
            val picker = CorePicker(rows, day.number.toLong(), clock.hours(at, day))
            val found = picker.usual().toSet()
            return Usual(picker, pours.filterKeys { it in found })
        }
    }
}

/** The picker's arithmetic, apart from any screen so it can be tested. */
object Picker {
    /** When each of the day's drinks was last logged. */
    fun recency(pours: List<Entry>): Map<String, Instant> {
        val recency = HashMap<String, Instant>()
        for (pour in pours) recency.merge(pour.serveKey, pour.timestamp, ::maxOf)
        return recency
    }

    /**
     * The day's drinks, most recent first, then the favourites in pinned order, the serves usually drunk at this time,
     * the generic drinks in their common sizes and Units, each shown once. When searching, every size of every matching
     * drink, its pinned price where it has one, those usually drunk at this time first. Hidden drinks show only if logged that day.
     */
    fun tiles(query: String, favourites: List<FavouriteItem>, drinks: List<Drink>, pours: List<Entry>, recency: Map<String, Instant>, usual: Usual): List<Serve> {
        val folded = query.trim().searchFolded
        val shown = favourites.filter { !it.drink.isHidden }
        // Units was pinned on installs that seeded it and cannot be unpinned, so it keeps its place after the generics.
        val order = shown.filter { it.drink.category != DrinkCategory.UNITS }.map { it.serve.id }
        if (folded.isEmpty()) {
            val generics = Generics.serves(drinks)
            val live = drinks.associateBy { it.id }
            val serves = HashMap<String, Serve>()
            for ((key, pour) in usual.pours) {
                val drink = live[pour.drinkId]?.takeIf { !it.isHidden } ?: continue
                serves[key] = Serve(drink, pour.vessel, pour.volumeMl)
            }
            for (serve in generics) serves[serve.id] = serve
            for (entry in pours) serves[entry.serveKey] = Serve(entry.drink, entry.vessel, entry.volumeMl, entry.price)
            for (item in shown) serves[item.serve.id] = item.serve
            val added = recency.entries.sortedByDescending { it.value }.map { it.key }
            return usual.picker.tiles(added, order, generics.map { it.id }, pours.map { it.serveKey }).mapNotNull { serves[it] }
        }
        val serves = (drinks + Generics.unstored(drinks))
            .filter { !it.isHidden && (it.name.searchFolded.contains(folded) || it.category.label.searchFolded.contains(folded)) }
            .flatMap { drink ->
                // Every size it comes in, not only the one it was added as, so a drink found by name can be logged at
                // any size without going through the options sheet.
                val pinned = shown.filter { it.drink.id == drink.id }
                drink.sizes(ServeSize(drink.vessel, drink.volumeMl)).map { size ->
                    pinned.firstOrNull { it.favourite.vessel == size.vessel && it.favourite.volumeMl == size.ml }?.serve
                        ?: Serve(drink, size.vessel, size.ml)
                }
            }
        val byId = serves.associateBy { it.id }
        return usual.picker.rank(serves.map { it.id }, order).mapNotNull { byId[it] }
    }

    /** Catalogue serves matching the search, less brands the user already has as drinks. */
    fun catalogMatches(query: String, drinks: List<Drink>): List<CatalogItem> {
        if (query.isBlank()) return emptyList()
        val owned = drinks.mapTo(HashSet()) { Catalog.key(it.name, it.category) }
        return Catalog.search(query).filter { Catalog.key(it.name, it.category) !in owned }
    }

    /**
     * The pressed drink first, then the user's other drinks of the same kind (generics first), then catalogue brands
     * not yet adopted.
     */
    fun choices(base: Drink, query: String, drinks: List<Drink>): List<Choice> {
        val folded = query.trim().searchFolded
        fun matches(name: String) = folded.isEmpty() || name.searchFolded.contains(folded)
        val kind = base.category
        val yours = (drinks + Generics.unstored(drinks))
            .filter { it.id != base.id && it.category == kind && !it.isHidden && matches(it.name) }
            .sortedWith(compareBy<Drink> { !it.isGeneric }.thenBy { it.name })
        val owned = drinks.mapTo(HashSet()) { Catalog.key(it.name, it.category) }
        val catalog = (Catalog.brandsByCategory[kind] ?: emptyList())
            .filter { matches(it.name) && Catalog.key(it.name, it.category) !in owned }
        return listOf(Choice(base)) + yours.map(::Choice) + catalog.map(::Choice)
    }

    /**
     * Several drinks run from the chosen time up to now, or 20 minutes apart on a past day (closer if that would run past
     * the end of the day, since each is put on the day its time falls in).
     */
    fun spreadTimes(time: Instant, count: Int, day: DayKey, clock: DayClock, now: Instant = Instant.now()): List<Instant> {
        if (count <= 1) return listOf(time)
        val gapMillis = if (day == clock.day(now) && now > time) {
            Duration.between(time, now).toMillis() / (count - 1)
        } else {
            val room = (Duration.between(time, clock.end(day)).toMillis() - 60_000).coerceAtLeast(0)
            minOf(20 * 60_000L, room / (count - 1))
        }
        return (0 until count).map { time.plusMillis(gapMillis * it) }
    }

    fun isUnits(serve: Serve) = serve.drink.category == DrinkCategory.UNITS
}
