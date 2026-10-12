package cc.blit.groglog.ui.log

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import cc.blit.groglog.container
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
import cc.blit.groglog.model.FavouriteItem
import cc.blit.groglog.model.Ledger
import cc.blit.groglog.model.Serve
import cc.blit.groglog.model.ServeSize
import cc.blit.groglog.model.searchFolded
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.ExperimentalCoroutinesApi
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
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

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
    queries: Queries,
    prefs: Prefs,
    private val logbook: suspend () -> Logbook,
    fixedDay: DayKey? = null,
) : ViewModel() {
    var search by mutableStateOf("")

    private val appeared = MutableStateFlow(0)

    /**
     * Recency as of when the screen appeared, so tapping a tile does not reorder the grid while it is in use. Deliberate
     * picks (the options sheet, a catalogue result) move to the front straight away.
     */
    private val recency = MutableStateFlow<Map<String, Instant>?>(null)
    private val pulses = MutableStateFlow(emptyMap<String, Int>())

    private val settings = prefs.settings

    private val day: Flow<DayKey> =
        if (fixedDay != null) flowOf(fixedDay) else combine(settings, appeared) { it, _ -> it.clock.today }.distinctUntilChanged()

    private val content: StateFlow<Content?> =
        combine(queries.favourites(), queries.drinks(), day.flatMapLatest { day -> queries.entries(day..day).map { day to it } }) { favourites, drinks, (day, pours) ->
            Content(day, favourites, drinks, pours)
        }.stateIn(viewModelScope, SharingStarted.Eagerly, null)

    private val ledger = combine(queries.days(), settings) { days, settings -> Ledger(days, settings.clock) to settings.currency }

    val state: StateFlow<LogState?> =
        combine(content.filterNotNull(), ledger, snapshotFlow { search }, recency, pulses) { content, (ledger, currency), query, frozen, pulses ->
            val order = frozen ?: Picker.recency(content.favourites, content.pours)
            LogState(
                day = content.day,
                ledger = ledger,
                currency = currency,
                query = query,
                favourites = content.favourites,
                drinks = content.drinks,
                pours = content.pours,
                tiles = Picker.tiles(query, content.favourites, content.drinks, content.pours, order),
                catalog = Picker.catalogMatches(query, content.drinks),
                counts = content.pours.groupingBy { it.serveKey }.eachCount(),
                pulses = pulses,
            )
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    init {
        viewModelScope.launch {
            val first = content.filterNotNull().first()
            recency.compareAndSet(null, Picker.recency(first.favourites, first.pours))
        }
    }

    /** The screen came into view: re-anchor today, and take the order the grid will hold while it is used. */
    fun appeared() {
        appeared.update { it + 1 }
        content.value?.let { recency.value = Picker.recency(it.favourites, it.pours) }
    }

    /** Logs one now, or just after the day's last drink on a past day. */
    fun log(serve: Serve) {
        val state = state.value ?: return
        pulse(serve.id)
        val time = state.suggestedTime
        viewModelScope.launch { logbook().log(serve, listOf(time)) }
    }

    /** A round from the options sheet: several at chosen times, at a strength of its own, brought to the front. */
    fun log(serve: Serve, times: List<Instant>, abv: Double?) {
        bringForward(serve.id)
        pulse(serve.id)
        viewModelScope.launch { logbook().log(serve, times, abv) }
    }

    /** A catalogue pick becomes one of the user's drinks, logged at this size and brought to the front. */
    fun adopt(item: CatalogItem, currency: String) {
        search = ""
        viewModelScope.launch {
            val logbook = logbook()
            val price = item.price(currency)
            val drink = logbook.drink(item.name, item.category, item.abv, item.vessel, item.volumeMl, price) ?: return@launch
            val serve = Serve(drink, item.vessel, item.volumeMl, price)
            val time = state.value?.suggestedTime ?: Instant.now()
            bringForward(serve.id)
            pulse(serve.id)
            logbook.log(serve, listOf(time))
        }
    }

    fun logUnits(units: Double, time: Instant) {
        viewModelScope.launch { logbook().logUnits(units, time) }
    }

    /** Takes back the last `count` drinks logged on the day, latest first. */
    fun undo(count: Int = 1) {
        val day = state.value?.day ?: return
        viewModelScope.launch {
            val logbook = logbook()
            repeat(count) { logbook.undo(day) }
        }
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
    fun log(choice: Choice, size: ServeSize, price: Double, times: List<Instant>, abv: Double, currency: String) {
        viewModelScope.launch {
            val drink = resolve(logbook(), choice, size, currency) ?: return@launch
            log(Serve(drink, size.vessel, size.ml, price), times, abv)
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

    companion object {
        fun factory(fixedDay: DayKey? = null) = viewModelFactory {
            initializer {
                val container = this[APPLICATION_KEY]!!.container
                LogViewModel(container.queries, container.prefs, container::logbook, fixedDay)
            }
        }
    }
}

/** The picker's arithmetic, apart from any screen so it can be tested. */
object Picker {
    /** When each serve was last drunk: favourites by their last use, the day's drinks by their time. */
    fun recency(favourites: List<FavouriteItem>, pours: List<Entry>): Map<String, Instant> {
        val recency = HashMap<String, Instant>()
        for (item in favourites) {
            val used = item.favourite.lastUsed ?: continue
            recency.merge(item.serve.id, used, ::maxOf)
        }
        for (pour in pours) recency.merge(pour.serveKey, pour.timestamp, ::maxOf)
        return recency
    }

    /**
     * Favourites and the day's drinks or, when searching, every size of every matching drink, its pinned price where it
     * has one. Recently drunk first, then in favourite order. Hidden drinks show only if logged that day.
     */
    fun tiles(query: String, favourites: List<FavouriteItem>, drinks: List<Drink>, pours: List<Entry>, recency: Map<String, Instant>): List<Serve> {
        val folded = query.trim().searchFolded
        val shown = favourites.filter { !it.drink.isHidden }
        val serves: List<Serve> = if (folded.isEmpty()) {
            val list = shown.map { it.serve }.toMutableList()
            val ids = list.mapTo(HashSet()) { it.id }
            for (entry in pours) {
                if (ids.add(entry.serveKey)) list += Serve(entry.drink, entry.vessel, entry.volumeMl, entry.price)
            }
            list
        } else {
            drinks
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
        }
        val order = HashMap<String, Int>()
        shown.forEachIndexed { index, item -> order.putIfAbsent(item.serve.id, index) }
        return serves.sortedWith { a, b ->
            val x = recency[a.id]
            val y = recency[b.id]
            when {
                x != null && y != null -> y.compareTo(x)
                x != null -> -1
                y != null -> 1
                else -> (order[a.id] ?: Int.MAX_VALUE).compareTo(order[b.id] ?: Int.MAX_VALUE)
            }
        }
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
        val yours = drinks
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
