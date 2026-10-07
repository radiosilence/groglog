import GRDBQuery
import SwiftUI

/// Long-press on a tile: which drink exactly (one of the user's, or a UK brand of the same type), with a star to keep
/// it on the Log grid at this size. The size starts as the tile's and can be overridden from the drink's usual sizes.
struct LogOptionsSheet: View {
    let base: Serve
    let day: DayKey
    let ledger: Ledger
    /// Told the serve key of what was logged, so the picker can bring it to the front.
    let onLog: (String) -> Void
    @Query(DrinksRequest()) private var drinks: [Drink]
    @Query(FavouritesRequest()) private var favourites: [FavouriteItem]
    @Environment(\.databaseContext) private var database
    @Environment(\.dismiss) private var dismiss
    @Environment(Prefs.self) private var prefs
    @State private var selected: String
    @State private var size: ServeSize
    @State private var count = 1
    @State private var time: Date
    @State private var search = ""
    @State private var editing: Drink?
    /// What this round cost, when it differs from the usual price. Nil follows the drink and the size, so picking
    /// a different one does not carry over the previous one's price.
    @State private var price: Double?
    /// The strength this round is logged at, when it differs from the drink's: a guest ale is logged as Beer at the
    /// pump clip's figure without making a drink of it. Nil follows the drink, so it resets when another is picked.
    @State private var abv: Double?

    init(base: Serve, day: DayKey, ledger: Ledger, after last: Date?, onLog: @escaping (String) -> Void) {
        self.base = base
        self.day = day
        self.ledger = ledger
        self.onLog = onLog
        _selected = State(initialValue: base.drink.id.uuidString)
        _size = State(initialValue: ServeSize(base.vessel, base.volumeMl))
        _time = State(initialValue: ledger.clock.suggestedTime(for: day, after: last))
    }

    var body: some View {
        let choices = self.choices
        let choice = choices.first { $0.id == selected } ?? choices[0]
        let usualPrice = usualPrice(for: choice)
        let strength = abv ?? choice.abv
        let pinned = Set(favourites.filter { $0.favourite.vessel == size.vessel && $0.favourite.volumeMl == size.ml }.map(\.drink.id))

        NavigationStack {
            Form {
                Section {
                    ChipRow(options: base.drink.sizes(including: ServeSize(base.vessel, base.volumeMl)), selection: $size) { $0.label }
                    if base.drink.category != .units {
                        NumberRow(label: "Strength", value: Binding(get: { strength }, set: { abv = $0 }), suffix: "% ABV")
                        NumberRow(label: "Units each", value: Binding(
                            get: { (Units.of(ml: size.ml, abv: strength) * 10).rounded() / 10 },
                            set: { abv = $0 * 1000 / size.ml }
                        ), suffix: "u")
                    }
                    // Placed under the size, since the size sets the price. Re-created when the drink or the size
                    // changes, so it shows the new usual price.
                    MoneyField(label: "Price", value: Binding(get: { price ?? usualPrice }, set: { price = $0 }), currency: prefs.currency)
                        .id("\(choice.id)|\(Int(size.ml))")
                    Stepper("How many: \(count)", value: $count, in: 1...12)
                    if day == ledger.today {
                        ChipRow(options: [0, 15, 30, 60, 120, 180], selection: minutesAgo) {
                            $0 == 0 ? "Now" : $0 < 60 ? "\(Int($0))m ago" : "\(Int($0 / 60))h ago"
                        }
                    }
                    DatePicker(count > 1 ? "First one at" : "At", selection: resolvedTime, displayedComponents: .hourAndMinute)
                } footer: {
                    let times = spreadTimes
                    if count > 1, let first = times.first, let last = times.last {
                        Text("Spread from \(first.formatted(date: .omitted, time: .shortened)) to \(last.formatted(date: .omitted, time: .shortened)).")
                    }
                }

                Section {
                    ForEach(choices) { option in
                        ChoiceRow(choice: option, ml: size.ml, isSelected: option.id == choice.id, isPinned: option.drink.map { pinned.contains($0.id) } ?? false) {
                            selected = option.id
                        } onStar: {
                            togglePin(option)
                        }
                        .contextMenu {
                            if let drink = option.drink {
                                Button("Edit \(drink.name)", systemImage: "pencil") { editing = drink }
                            }
                        }
                    }
                } header: {
                    Text("Which one?")
                }
            }
            // The search field sits in the bar above; without this, a headerless first section leaves a wide
            // empty gap under it.
            .contentMargins(.top, 8, for: .scrollContent)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a drink")
            .onChange(of: selected) { price = nil; abv = nil }
            .onChange(of: size) { price = nil }
            .navigationTitle(base.drink.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log \(count > 1 ? "\(count) " : "")· \((Units.of(ml: size.ml, abv: strength) * Double(count)).unitsText) u", role: .confirm) {
                        guard let drink = resolve(choice) else { return }
                        let serve = Serve(drink, size.vessel, size.ml, price: price ?? usualPrice)
                        database.logbook(prefs).log(serve, at: spreadTimes, abv: strength)
                        onLog(serve.id)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!Units.isStrength(strength))
                }
            }
            .sheet(item: $editing) { DrinkEditor(drink: $0) }
        }
        .animation(.snappy, value: count)
    }

    /// The pressed drink first, then the user's other drinks of the same kind, then catalogue brands not yet adopted.
    private var choices: [Choice] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matches = { (name: String) in query.isEmpty || name.localizedStandardContains(query) }
        let kind = base.drink.category
        let yours = drinks
            .filter { $0.id != base.drink.id && $0.category == kind && !$0.isHidden && matches($0.name) }
            .sorted { $0.isGeneric != $1.isGeneric ? $0.isGeneric : $0.name < $1.name }
        let owned = Set(drinks.map { Catalog.key($0.name, $0.category) })
        let catalog = (Catalog.brandsByCategory[kind] ?? []).filter { brand in
            matches(brand.name) && !owned.contains(Catalog.key(brand.name, brand.category))
        }
        return [Choice(base.drink)] + yours.map(Choice.init) + catalog.map(Choice.init)
    }

    /// What this drink at this size normally costs: its pinned price, else its own price scaled to the size,
    /// else the catalogue price for a brand not yet adopted.
    private func usualPrice(for choice: Choice) -> Double {
        if let pinned = favourite(for: choice)?.price { return pinned }
        if let drink = choice.drink { return drink.price(for: size.vessel, ml: size.ml) }
        return choice.brand.map { Catalog.price($0, size.vessel, size.ml, currency: prefs.currency) } ?? 0
    }

    private func favourite(for choice: Choice) -> Favourite? {
        guard let drink = choice.drink else { return nil }
        return favourites.first { $0.drink.id == drink.id && $0.favourite.vessel == size.vessel && $0.favourite.volumeMl == size.ml }?.favourite
    }

    private func togglePin(_ choice: Choice) {
        let logbook = database.logbook(prefs)
        if let pinned = favourite(for: choice) {
            logbook.unpin(pinned)
        } else if let drink = resolve(choice) {
            logbook.pin(Serve(drink, size.vessel, size.ml))
        }
    }

    /// Catalogue picks become the user's own drinks, first logged at this size.
    private func resolve(_ choice: Choice) -> Drink? {
        if let drink = choice.drink { return drink }
        let price = choice.brand.map { Catalog.price($0, size.vessel, size.ml, currency: prefs.currency) } ?? 0
        let drink = database.logbook(prefs).drink(named: choice.name, category: choice.category, abv: choice.abv, vessel: size.vessel, volumeMl: size.ml, price: price)
        if let drink { selected = drink.id.uuidString }
        return drink
    }

    /// Several drinks run from the chosen time up to now (or 20 minutes apart on a past day, closer if that would run
    /// past the end of the day, since each is put on the day its time falls in).
    private var spreadTimes: [Date] {
        guard count > 1 else { return [time] }
        let now = Date.now
        let gap = day == ledger.today && now > time
            ? now.timeIntervalSince(time) / Double(count - 1)
            : min(20 * 60, max(0, ledger.clock.end(of: day).timeIntervalSince(time) - 60) / Double(count - 1))
        return (0..<count).map { time.addingTimeInterval(gap * Double($0)) }
    }

    private var minutesAgo: Binding<Double> {
        Binding(
            get: { (Date.now.timeIntervalSince(time) / 60 / 15).rounded() * 15 },
            set: { time = Date.now.addingTimeInterval(-$0 * 60) }
        )
    }

    private var resolvedTime: Binding<Date> {
        Binding(get: { time }, set: { time = ledger.clock.resolve($0, into: day) })
    }
}

/// One of the user's drinks or a catalogue brand, presented the same way.
private struct Choice: Identifiable {
    let id: String
    let name: String
    let category: DrinkCategory
    let abv: Double
    var drink: Drink?
    /// Kept so a catalogue pick can be priced at whichever size is chosen.
    var brand: CatalogBrand?

    init(_ drink: Drink) {
        id = drink.id.uuidString
        name = drink.name
        category = drink.category
        abv = drink.abv
        self.drink = drink
    }

    init(_ brand: CatalogBrand) {
        id = "catalog|\(brand.name)"
        name = brand.name
        category = brand.category
        abv = brand.abv
        self.brand = brand
    }
}

private struct ChoiceRow: View {
    let choice: Choice
    let ml: Double
    let isSelected: Bool
    let isPinned: Bool
    let onSelect: () -> Void
    let onStar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(choice.name).fontWeight(isSelected ? .semibold : .regular)
                        Text("\(choice.abv.abvText) · \(Units.of(ml: ml, abv: choice.abv).unitsText) u")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark").foregroundStyle(Color.grog).fontWeight(.semibold)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(isPinned ? "Remove from Log grid" : "Add to Log grid", systemImage: isPinned ? "star.fill" : "star", action: onStar)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(isPinned ? Color.grog : .secondary)
                .sensoryFeedback(.selection, trigger: isPinned)
        }
    }
}
