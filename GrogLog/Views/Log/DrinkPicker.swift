import SwiftData
import SwiftUI

/// The logging surface: generics and favourite brands, most recently drunk first.
/// Tap logs one now; long-press to pick a specific brand, size, time or count.
struct DrinkPicker: View {
    let day: Date
    let ledger: Ledger
    @Query(filter: #Predicate<Drink> { !$0.isHidden }, sort: \Drink.order) private var drinks: [Drink]
    @Environment(\.modelContext) private var context
    @State private var search = ""
    @State private var options: Drink?
    @State private var countingUnits = false
    @State private var creating = false
    @State private var logged = 0

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        let pours = ledger.pours(on: day)
        let countByDrink = Dictionary(grouping: pours.compactMap(\.drinkID)) { $0 }.mapValues(\.count)

        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(matchingDrinks) { drink in
                    DrinkTile(category: drink.category, vessel: drink.vessel, volumeMl: drink.volumeMl, name: drink.name, abv: drink.abv, count: countByDrink[drink.id] ?? 0)
                        .onTapGesture { drink.category == .units ? countingUnits = true : log(drink) }
                        .onLongPressGesture(minimumDuration: 0.35) { drink.category == .units ? countingUnits = true : (options = drink) }
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
                        DrinkTile(category: item.category, vessel: item.vessel, volumeMl: item.volumeMl, name: item.name, abv: item.abv, count: 0)
                            .onTapGesture { log(adopt(item)) }
                    }
                }
                .padding(.horizontal)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Stella, Rioja, pint…")
        .safeAreaInset(edge: .bottom) {
            DaySummaryBar(day: day, ledger: ledger)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New drink", systemImage: "plus") { creating = true }
            }
        }
        .sheet(item: $options) { drink in
            LogOptionsSheet(base: drink, day: day, ledger: ledger)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $countingUnits) {
            UnitsSheet(day: day, ledger: ledger, drinkID: drinks.first { $0.category == .units }?.id)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $creating) {
            DrinkEditor(drink: nil)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: logged)
    }

    /// Generics and favourites — or, when searching, every drink that matches. Recently drunk first.
    private var matchingDrinks: [Drink] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return drinks
            .filter { query.isEmpty ? $0.isGeneric || $0.isFavourite : $0.name.localizedStandardContains(query) || $0.category.label.localizedStandardContains(query) }
            .sorted { a, b in
                switch (ledger.lastPoured[a.id], ledger.lastPoured[b.id]) {
                case let (x?, y?): x > y
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): a.order < b.order
                }
            }
    }

    private var catalogMatches: [CatalogItem] {
        Catalog.search(search).filter { item in
            !drinks.contains { $0.name == item.name && $0.vessel == item.vessel && $0.volumeMl == item.volumeMl }
        }
    }

    private func log(_ drink: Drink) {
        let last = ledger.pours(on: day).last?.timestamp
        context.insert(Pour(drink: drink, at: ledger.clock.suggestedTime(for: day, after: last)))
        context.setAlcoholFree(false, on: day)
        logged += 1
    }

    /// Catalogue picks become your own drinks, so they show up first next time and can be corrected.
    private func adopt(_ item: CatalogItem) -> Drink {
        let drink = Drink(name: item.name, category: item.category, vessel: item.vessel, volumeMl: item.volumeMl, abv: item.abv)
        context.insert(drink)
        search = ""
        return drink
    }
}

private struct DrinkTile: View {
    let category: DrinkCategory
    let vessel: Vessel
    let volumeMl: Double
    let name: String
    let abv: Double
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            DrinkGlyph(category: category, vessel: vessel, volumeMl: volumeMl)
                .frame(height: 58)
                .padding(.bottom, 4)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
            Text(category.serving(ml: volumeMl, abv: abv))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Units.of(ml: volumeMl, abv: abv).unitsText) u")
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
    let day: Date
    let ledger: Ledger
    @Environment(\.modelContext) private var context

    var body: some View {
        let pours = ledger.pours(on: day)
        let totals = DayTotals(pours)
        let status = ledger.status(on: day)

        HStack {
            switch status {
            case .drank:
                Text("\(totals.count) \(totals.count == 1 ? "drink" : "drinks") · \(Text("\(totals.units.unitsText) u").bold())")
                Spacer()
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    if let last = pours.last { context.delete(last) }
                }
                .labelStyle(.iconOnly)
            case .alcoholFree:
                Label("Alcohol-free", systemImage: "leaf.fill").foregroundStyle(Color.dry)
                Spacer()
                Button("Undo") { context.setAlcoholFree(false, on: day) }
            case .today, .unlogged, .untracked:
                Text("Nothing logged").foregroundStyle(.secondary)
                Spacer()
                Button("Alcohol-free", systemImage: "leaf") { context.setAlcoholFree(true, on: day) }
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
