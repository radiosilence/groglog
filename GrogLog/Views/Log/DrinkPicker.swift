import GRDB
import GRDBQuery
import GrogLogCore
import SwiftUI

/// The logging surface: anything already logged that day, the Log-grid favourites, what is usually drunk at this time,
/// then the generic drinks in their common sizes and Units, each a drink in a size. Tap logs one now; long-press to
/// change the drink, size, time or count.
struct DrinkPicker: View {
    let day: DayKey
    let ledger: Ledger
    @Query(FavouritesRequest()) private var favourites: [FavouriteItem]
    @Query(DrinksRequest()) private var drinks: [Drink]
    @Query<EntriesRequest> private var pours: [Entry]
    @Environment(\.databaseContext) private var database
    @Environment(Prefs.self) private var prefs
    @State private var search = ""
    @State private var options: Serve?
    @State private var countingUnits = false
    @State private var creating = false
    @State private var logged = 0
    /// The day's drinks as of when the screen appeared, so tapping a tile does not reorder the grid while it is in
    /// use. Deliberate picks (the long-press sheet, a search result) jump to the front straight away.
    @State private var recency: [String: Date] = [:]
    /// The whole history scored for the moment a drink would be logged, taken when the screen appeared for the same
    /// reason, with a pour of each serve it found usual. Nil until the first scoring lands, and the grid waits for it
    /// rather than drawing a tile that would then move.
    @State private var picker: CorePicker?
    @State private var usual: [String: Pour] = [:]
    /// Bumped per tile each time it is logged, to play the pour.
    @State private var pulses: [String: Int] = [:]

    /// Grows with the text size, so the tiles go to fewer columns rather than clipping their names.
    @ScaledMetric private var tileWidth = 104.0

    init(day: DayKey, ledger: Ledger) {
        self.day = day
        self.ledger = ledger
        _pours = Query(constant: EntriesRequest(days: day...day))
    }

    var body: some View {
        let counts = Dictionary(grouping: pours, by: \.serveKey).mapValues(\.count)
        let columns = [GridItem(.adaptive(minimum: tileWidth), spacing: 12)]

        ScrollView {
            let tiles = self.tiles
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tiles) { serve in
                    let isUnits = serve.drink.category == .units
                    DrinkTile(serve: serve, count: counts[serve.id] ?? 0, pulse: pulses[serve.id] ?? 0)
                        .onTapGesture { isUnits ? countingUnits = true : log(serve) }
                        .onLongPressGesture(minimumDuration: 0.35) { isUnits ? countingUnits = true : (options = serve) }
                        .accessibilityAction(named: "Options") { isUnits ? countingUnits = true : (options = serve) }
                }
            }
            .padding(.horizontal)
            .animation(search.isEmpty ? .snappy(duration: 0.4) : nil, value: tiles.map(\.id))

            let catalog = catalogMatches
            if !catalog.isEmpty {
                Text("UK drinks")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top])
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(catalog) { item in
                        DrinkTile(name: item.name, category: item.category, vessel: item.vessel, volumeMl: item.volumeMl, abv: item.abv, count: 0)
                            .onTapGesture {
                                guard let serve = adopt(item) else { return }
                                log(serve)
                                recency[serve.id] = .now
                            }
                    }
                }
                .padding(.horizontal)
            }

            let query = search.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty && tiles.isEmpty && catalog.isEmpty {
                ContentUnavailableView {
                    Label("No matches for \u{201C}\(query)\u{201D}", systemImage: "magnifyingglass")
                } description: {
                    Text("Add it as a drink with its own strength and size.")
                } actions: {
                    Button("Add \u{201C}\(query)\u{201D}") { creating = true }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 40)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Stella, Rioja, pint…")
        .safeAreaInset(edge: .bottom) {
            DaySummaryBar(day: day, ledger: ledger, pours: pours)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New drink", systemImage: "plus") { creating = true }
            }
        }
        .sheet(item: $options) { serve in
            LogOptionsSheet(base: serve, day: day, ledger: ledger, after: pours.last?.timestamp) { id in
                recency[id] = .now
                pulses[id, default: 0] += 1
            }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $countingUnits) {
            UnitsSheet(day: day, at: ledger.clock.suggestedTime(for: day, after: pours.last?.timestamp))
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $creating) {
            DrinkEditor(drink: nil, name: search.trimmingCharacters(in: .whitespaces))
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: logged)
        // Runs on each appearance and again when the day rolls over with the screen open.
        .task(id: day) {
            recency = Dictionary(pours.map { ($0.serveKey, $0.timestamp) }, uniquingKeysWith: max)
            await rank()
        }
    }

    /// The day's drinks, most recent first, then the favourites in pinned order, the serves usually drunk at this time,
    /// the generic drinks in their common sizes and Units, each shown once. When searching, the Log-grid sizes (or
    /// default size) of every matching drink, those usually drunk at this time first. Hidden drinks show only if logged that day.
    private var tiles: [Serve] {
        guard let picker else { return [] }
        let query = search.trimmingCharacters(in: .whitespaces)
        let favourites = favourites.filter { !$0.drink.isHidden }
        let order = favourites.map(\.serve.id)
        if query.isEmpty {
            let generics = Self.generics(drinks)
            // Built from the drinks as they are now, so an edit or a hide made with the screen open shows at once.
            let live = Dictionary(drinks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var serves: [String: Serve] = [:]
            for (key, pour) in usual {
                guard let drink = live[pour.drinkId], !drink.isHidden else { continue }
                serves[key] = Serve(drink, pour.vessel, pour.volumeMl)
            }
            for serve in generics { serves[serve.id] = serve }
            for entry in pours { serves[entry.serveKey] = Serve(entry.drink, entry.vessel, entry.volumeMl, price: entry.price) }
            for item in favourites { serves[item.serve.id] = item.serve }
            let added = recency.sorted { $0.value > $1.value }.map(\.key)
            return picker.tiles(added: added, favourites: order, generics: generics.map(\.id), logged: pours.map(\.serveKey))
                .compactMap { serves[$0] }
        }
        let serves = drinks
            .filter { !$0.isHidden && ($0.name.localizedStandardContains(query) || $0.category.label.localizedStandardContains(query)) }
            .flatMap { drink -> [Serve] in
                // Every size it comes in, not only the one it was added as, so a drink found by name can
                // be logged at any size without going through the long-press sheet.
                let pinned = favourites.filter { $0.drink.id == drink.id }
                return drink.sizes(including: ServeSize(drink.vessel, drink.volumeMl)).map { size in
                    pinned.first { $0.favourite.vessel == size.vessel && $0.favourite.volumeMl == size.ml }?.serve
                        ?? Serve(drink, size.vessel, size.ml)
                }
            }
        let byId = Dictionary(serves.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return picker.rank(keys: serves.map(\.id), favourites: order).compactMap { byId[$0] }
    }

    /// Every generic drink in its own size, then the other sizes it is commonly drunk in, then Units, so the grid can
    /// log anything with nothing pinned.
    nonisolated static func generics(_ drinks: [Drink]) -> [Serve] {
        let shown = drinks.filter { $0.isGeneric && !$0.isHidden }.sorted { $0.sortOrder < $1.sortOrder }
        let sized = shown.filter { $0.category != .units }.flatMap { drink in
            var seen = Set<ServeSize>()
            return ([ServeSize(drink.vessel, drink.volumeMl)] + Catalog.genericSizes(drink.category))
                .filter { seen.insert($0).inserted }
                .map { Serve(drink, $0.vessel, $0.ml) }
        }
        return sized + shown.filter { $0.category == .units }.map { Serve($0) }
    }

    /// Scores every serve ever logged for when the next drink would go: now for today, or that evening on a past day.
    /// The history grows without bound, so it is read and scored off the main thread.
    private func rank() async {
        let clock = ledger.clock
        let day = day
        let time = clock.suggestedTime(for: day, after: pours.last?.timestamp)
        guard let reader = try? database.reader,
              let (picker, usual) = try? await reader.read({ db in try Self.score(db, clock: clock, day: day, at: time) })
        else { return }
        self.picker = picker
        self.usual = usual
    }

    /// Hidden drinks are left out, so they never come back as usual.
    private nonisolated static func score(_ db: Database, clock: DayClock, day: DayKey, at time: Date) throws -> (CorePicker, [String: Pour]) {
        let hidden = try Set(Drink.filter(Column("isHidden")).fetchAll(db).map(\.id))
        var hours = HourCounter(clock)
        var pours: [String: Pour] = [:]
        var rows: [PickerPour] = []
        for pour in try Pour.fetchAll(db) where !hidden.contains(pour.drinkId) {
            let key = Serve.key(pour.drinkId, pour.vessel, pour.volumeMl)
            if pours[key] == nil { pours[key] = pour }
            rows.append(PickerPour(key: key, day: Int64(pour.day), hours: hours.hours(pour.timestamp, into: pour.dayKey)))
        }
        let picker = CorePicker(history: rows, day: Int64(day.number), hours: clock.hours(time, into: day))
        let found = Set(picker.usual())
        return (picker, pours.filter { found.contains($0.key) })
    }

    private var catalogMatches: [CatalogItem] {
        let owned = Set(drinks.map { Catalog.key($0.name, $0.category) })
        return Catalog.search(search).filter { !owned.contains(Catalog.key($0.name, $0.category)) }
    }

    /// The write is a transaction on the main thread, well inside a frame however long the log (`ScaleTests` times
    /// it), so the pour and the drink landing are the same frame.
    private func log(_ serve: Serve) {
        pulses[serve.id, default: 0] += 1
        logged += 1
        database.logbook(prefs).log(serve, at: [ledger.clock.suggestedTime(for: day, after: pours.last?.timestamp)])
    }

    /// A catalogue pick becomes one of the user's drinks, first logged at this size.
    private func adopt(_ item: CatalogItem) -> Serve? {
        search = ""
        let price = item.price(in: prefs.currency)
        return database.logbook(prefs).drink(named: item.name, category: item.category, abv: item.abv, vessel: item.vessel, volumeMl: item.volumeMl, price: price)
            .map { Serve($0, item.vessel, item.volumeMl, price: price) }
    }
}

private struct DrinkTile: View {
    let name: String
    let category: DrinkCategory
    let vessel: Vessel
    let volumeMl: Double
    let abv: Double
    let count: Int
    var pulse = 0

    private var units: Double { Units.of(ml: volumeMl, abv: abv) }

    private var spoken: String {
        let serve: [String] = category == .units ? [] : [vessel.label(ml: volumeMl), abv.abvText, units.unitsText + " units"]
        let logged: [String] = count > 0 ? ["\(count) logged"] : []
        return (serve + logged).joined(separator: ", ")
    }

    var body: some View {
        KeyframeAnimator(initialValue: Pour(), trigger: pulse) { pour in
            card(pour)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.92, duration: 0.09)
                SpringKeyframe(1, duration: 0.45, spring: .bouncy(duration: 0.45, extraBounce: 0.1))
            }
            KeyframeTrack(\.fill) {
                CubicKeyframe(0.15, duration: 0.12)
                SpringKeyframe(1, duration: 0.5, spring: .smooth(duration: 0.5))
            }
            KeyframeTrack(\.tilt) {
                CubicKeyframe(-8, duration: 0.12)
                SpringKeyframe(0, duration: 0.45, spring: .bouncy(duration: 0.45))
            }
            KeyframeTrack(\.badge) {
                LinearKeyframe(1, duration: 0.15)
                CubicKeyframe(1.3, duration: 0.1)
                SpringKeyframe(1, duration: 0.35, spring: .bouncy(duration: 0.35))
            }
            KeyframeTrack(\.rise) {
                LinearKeyframe(0, duration: 0)
                CubicKeyframe(1, duration: 0.8)
            }
        }
        .contentShape(.rect(cornerRadius: 20))
        // Its own words rather than the tile's text combined, which would also read the "+2.3 u" that floats off it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(spoken)
        .accessibilityHint(category == .units ? "Enter a number of units" : "Logs one")
        .accessibilityAddTraits(.isButton)
    }

    private func card(_ pour: Pour) -> some View {
        VStack(spacing: 4) {
            DrinkGlyph(category: category, vessel: vessel, volumeMl: volumeMl, fill: pour.fill)
                .rotationEffect(.degrees(pour.tilt), anchor: .bottom)
                .frame(height: 58)
                .padding(.bottom, 4)
            // A seventh of the catalogue is a brewery's name plus a beer's, and the beer's name is what tells
            // them apart: truncated at the end, six Westons ciders would all read "Henry Westons Vi…". So the
            // name shrinks to fit first, then truncates in the middle, where the least is lost.
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.7)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
            Text(category.serving(vessel, ml: volumeMl, abv: abv))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(category == .units ? "type it in" : "\(units.unitsText) u")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.grog)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            if count > 0 {
                Text("×\(count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(count)))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.grog, in: .capsule)
                    .scaleEffect(pour.badge)
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.snappy, value: count)
            }
        }
        .overlay(alignment: .top) {
            if pour.rise < 1 {
                Text("+\(units.unitsText) u")
                    .font(.headline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Color.grog)
                    .offset(y: -44 * pour.rise)
                    .opacity(1 - pour.rise)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(pour.scale)
    }

    /// One logged drink's worth of motion.
    private struct Pour {
        var scale = 1.0
        var fill = 1.0
        var tilt = 0.0
        var rise = 1.0
        var badge = 1.0
    }
}

private extension DrinkTile {
    init(serve: Serve, count: Int, pulse: Int) {
        self.init(name: serve.drink.name, category: serve.drink.category, vessel: serve.vessel, volumeMl: serve.volumeMl, abv: serve.drink.abv, count: count, pulse: pulse)
    }
}

/// What is logged for the day so far, with undo, or a one-tap alcohol-free mark when nothing is.
private struct DaySummaryBar: View {
    let day: DayKey
    let ledger: Ledger
    let pours: [Entry]
    @Environment(\.databaseContext) private var database
    @Environment(Prefs.self) private var prefs

    var body: some View {
        let logbook = database.logbook(prefs)
        let totals = ledger.totals(on: day)
        let status = ledger.status(on: day)

        // The icon-only Undo brings its own 44pt target; the text buttons need the inset themselves.
        let trailingInset: CGFloat = status == .drank ? 6 : 18

        HStack {
            switch status {
            case .drank:
                Text("\(totals.count) \(totals.count == 1 ? "drink" : "drinks") · \(Text("\(totals.units.unitsText) u").bold())")
                Spacer()
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    logbook.undo(on: day)
                }
                .labelStyle(.iconOnly)
                // A full-size target, or a near miss lands on the tile behind the bar. It spills into the
                // bar's own padding rather than setting its height, so the capsule sits under the tab bar.
                .frame(width: 44, height: 44)
                .contentShape(.rect)
                .padding(.vertical, -6)
            case .alcoholFree:
                Label("Alcohol-free", systemImage: "leaf.fill").foregroundStyle(Color.dry)
                Spacer()
                Button("Undo") { logbook.setAlcoholFree(false, on: day) }
            case .today, .unlogged, .untracked:
                Text("Nothing logged").foregroundStyle(.secondary)
                Spacer()
                Button("Alcohol-free", systemImage: "leaf") { logbook.setAlcoholFree(true, on: day) }
                    .tint(.dry)
            case .future:
                EmptyView()
            }
        }
        .font(.subheadline.monospacedDigit())
        .contentTransition(.numericText())
        .animation(.snappy, value: totals.units)
        .frame(minHeight: 32)
        .padding(.leading, 18)
        .padding(.trailing, trailingInset)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}
