import GRDBQuery
import SwiftUI

/// The logging surface: your Log-grid favourites plus anything already logged that day, each a drink in a size,
/// most recently drunk first. Tap logs one now; long-press to change the drink, size, time or count.
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
    /// Recency as of when the screen appeared, so tapping a tile doesn't shuffle the grid under your thumb.
    /// Deliberate picks (the long-press sheet, a search result) jump to the front straight away.
    @State private var recency: [String: Date] = [:]
    /// Bumped per tile each time it's logged, to play the pour.
    @State private var pulses: [String: Int] = [:]

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    init(day: DayKey, ledger: Ledger) {
        self.day = day
        self.ledger = ledger
        _pours = Query(constant: EntriesRequest(days: day...day))
    }

    var body: some View {
        let counts = Dictionary(grouping: pours, by: \.serveKey).mapValues(\.count)

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
            DrinkEditor(drink: nil)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: logged)
        .onAppear {
            recency = Dictionary(favourites.compactMap { item in
                item.favourite.lastUsed.map { (item.serve.id, $0) }
            }, uniquingKeysWith: max)
            for pour in pours { recency[pour.serveKey] = max(recency[pour.serveKey] ?? .distantPast, pour.timestamp) }
        }
    }

    /// Favourites and the day's drinks — or, when searching, the Log-grid sizes (or default size) of every drink that matches.
    /// Recently drunk first, then in favourite order. Hidden drinks only show if had that day.
    private var tiles: [Serve] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let favourites = favourites.filter { !$0.drink.isHidden }
        var serves: [Serve]
        if query.isEmpty {
            serves = favourites.map(\.serve)
            for entry in pours where !serves.contains(where: { $0.id == entry.serveKey }) {
                serves.append(Serve(entry.drink, entry.vessel, entry.volumeMl, price: entry.price))
            }
        } else {
            serves = drinks
                .filter { !$0.isHidden && ($0.name.localizedStandardContains(query) || $0.category.label.localizedStandardContains(query)) }
                .flatMap { drink -> [Serve] in
                    // Every size it comes in, not just the one it was added as. Searching for Leffe and
                    // getting only the bottle meant long-pressing a pint of something else to find it,
                    // or picking the bottle and changing the size — for a drink you'd named exactly.
                    let pinned = favourites.filter { $0.drink.id == drink.id }
                    return drink.category.sizes(including: ServeSize(drink.vessel, drink.volumeMl)).map { size in
                        pinned.first { $0.favourite.vessel == size.vessel && $0.favourite.volumeMl == size.ml }?.serve
                            ?? Serve(drink, size.vessel, size.ml)
                    }
                }
        }
        let order = Dictionary(favourites.enumerated().map { ($1.serve.id, $0) }, uniquingKeysWith: min)
        return serves.sorted { a, b in
            switch (recency[a.id], recency[b.id]) {
            case let (x?, y?): x > y
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): (order[a.id] ?? .max) < (order[b.id] ?? .max)
            }
        }
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

    /// A catalogue pick becomes one of your drinks, first had at this size.
    private func adopt(_ item: CatalogItem) -> Serve? {
        search = ""
        return database.logbook(prefs).drink(named: item.name, category: item.category, abv: item.abv, vessel: item.vessel, volumeMl: item.volumeMl, price: item.price)
            .map { Serve($0, item.vessel, item.volumeMl, price: item.price) }
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func card(_ pour: Pour) -> some View {
        VStack(spacing: 4) {
            DrinkGlyph(category: category, vessel: vessel, volumeMl: volumeMl, fill: pour.fill)
                .rotationEffect(.degrees(pour.tilt), anchor: .bottom)
                .frame(height: 58)
                .padding(.bottom, 4)
            // A seventh of the catalogue is a brewery's name plus a beer's, and the beer's is the half that
            // tells them apart — six Westons ciders all read "Henry Westons Vi…" otherwise. So it shrinks
            // to fit before it gives up, and gives up in the middle, where the least is lost.
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

/// What's logged for the day so far, with undo — or a one-tap alcohol-free mark when there's nothing.
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
