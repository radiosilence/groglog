import SwiftData
import SwiftUI

/// The logging surface: your Log-grid favourites plus anything already logged that day, each a drink in a size,
/// most recently drunk first. Tap logs one now; long-press to change the drink, size, time or count.
struct DrinkPicker: View {
    let day: DayKey
    let ledger: Ledger
    @Query(sort: \Favourite.order) private var favourites: [Favourite]
    @Query(sort: \Drink.order) private var drinks: [Drink]
    @Query private var pours: [Pour]
    @Environment(\.modelContext) private var context
    @Environment(Prefs.self) private var prefs
    @State private var search = ""
    @State private var options: Serve?
    @State private var countingUnits = false
    @State private var creating = false
    @State private var logged = 0
    /// Recency as of when the screen appeared, so tapping a tile doesn't shuffle the grid under your thumb.
    /// Deliberate picks (the long-press sheet, a search result) jump to the front straight away.
    @State private var recency: [String: Date] = [:]

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    init(day: DayKey, ledger: Ledger) {
        self.day = day
        self.ledger = ledger
        _pours = Query(Pour.on(day...day))
    }

    var body: some View {
        let counts = Dictionary(grouping: pours, by: \.serveKey).mapValues(\.count)

        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tiles) { serve in
                    DrinkTile(serve: serve, count: counts[serve.id] ?? 0)
                        .onTapGesture { serve.drink.category == .units ? countingUnits = true : log(serve) }
                        .onLongPressGesture(minimumDuration: 0.35) { serve.drink.category == .units ? countingUnits = true : (options = serve) }
                }
            }
            .padding(.horizontal)

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
                                let serve = adopt(item)
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
            LogOptionsSheet(base: serve, day: day, ledger: ledger, after: pours.last?.timestamp) { recency[$0] = .now }
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
            recency = Dictionary(favourites.compactMap { favourite in
                favourite.lastUsed.flatMap { used in favourite.drink.map { (Serve.key($0.id, favourite.vessel, favourite.volumeMl), used) } }
            }, uniquingKeysWith: max)
            for pour in pours { recency[pour.serveKey] = max(recency[pour.serveKey] ?? .distantPast, pour.timestamp) }
        }
    }

    /// Favourites and the day's drinks — or, when searching, the Log-grid sizes (or default size) of every drink that matches.
    /// Recently drunk first, then in favourite order.
    private var tiles: [Serve] {
        let query = search.trimmingCharacters(in: .whitespaces)
        var serves: [Serve]
        if query.isEmpty {
            serves = favourites.filter { $0.drink != nil }.map(Serve.init)
            for pour in pours where !serves.contains(where: { $0.id == pour.serveKey }) {
                if let drink = pour.drink { serves.append(Serve(drink, pour.vessel, pour.volumeMl, price: pour.price)) }
            }
        } else {
            serves = drinks
                .filter { $0.name.localizedStandardContains(query) || $0.category.label.localizedStandardContains(query) }
                .flatMap { drink in
                    let pinned = favourites.filter { $0.drink == drink }.map(Serve.init)
                    return pinned.isEmpty ? [Serve(drink)] : pinned
                }
        }
        let order = Dictionary(favourites.enumerated().compactMap { index, favourite in
            favourite.drink.map { (Serve.key($0.id, favourite.vessel, favourite.volumeMl), index) }
        }, uniquingKeysWith: min)
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
        Catalog.search(search).filter { item in
            !drinks.contains { $0.name == item.name && $0.category == item.category }
        }
    }

    private func log(_ serve: Serve) {
        context.logbook(prefs).log(serve, at: [ledger.clock.suggestedTime(for: day, after: pours.last?.timestamp)])
        logged += 1
    }

    /// A catalogue pick becomes one of your drinks, first had at this size.
    private func adopt(_ item: CatalogItem) -> Serve {
        let drink = context.drink(named: item.name, category: item.category, abv: item.abv, vessel: item.vessel, volumeMl: item.volumeMl)
        search = ""
        return Serve(drink, item.vessel, item.volumeMl)
    }
}

private struct DrinkTile: View {
    let name: String
    let category: DrinkCategory
    let vessel: Vessel
    let volumeMl: Double
    let abv: Double
    let count: Int

    init(name: String, category: DrinkCategory, vessel: Vessel, volumeMl: Double, abv: Double, count: Int) {
        self.name = name
        self.category = category
        self.vessel = vessel
        self.volumeMl = volumeMl
        self.abv = abv
        self.count = count
    }

    init(serve: Serve, count: Int) {
        self.init(name: serve.drink.name, category: serve.drink.category, vessel: serve.vessel, volumeMl: serve.volumeMl, abv: serve.drink.abv, count: count)
    }

    var body: some View {
        VStack(spacing: 4) {
            DrinkGlyph(category: category, vessel: vessel, volumeMl: volumeMl)
                .frame(height: 58)
                .padding(.bottom, 4)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
            Text(category.serving(vessel, ml: volumeMl, abv: abv))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(category == .units ? "type it in" : "\(Units.of(ml: volumeMl, abv: abv).unitsText) u")
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
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.grog, in: .capsule)
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: count)
        .contentShape(.rect(cornerRadius: 20))
    }
}

/// What's logged for the day so far, with undo — or a one-tap alcohol-free mark when there's nothing.
private struct DaySummaryBar: View {
    let day: DayKey
    let ledger: Ledger
    let pours: [Pour]
    @Environment(\.modelContext) private var context
    @Environment(Prefs.self) private var prefs

    var body: some View {
        let logbook = context.logbook(prefs)
        let totals = ledger.totals(on: day)
        let status = ledger.status(on: day)

        HStack {
            switch status {
            case .drank:
                Text("\(totals.count) \(totals.count == 1 ? "drink" : "drinks") · \(Text("\(totals.units.unitsText) u").bold())")
                Spacer()
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    if let last = pours.last { logbook.delete(last) }
                }
                .labelStyle(.iconOnly)
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}
