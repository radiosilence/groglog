import SwiftData
import SwiftUI

/// Create or edit a drink. Picking a type fills in a sensible vessel, size and strength, so a new drink is usually type → name → done.
/// Edits a local copy saved on Done; Cancel discards.
struct DrinkEditor: View {
    let drink: Drink?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Prefs.self) private var prefs
    @State private var draft: DrinkDraft

    init(drink: Drink?) {
        self.drink = drink
        _draft = State(initialValue: drink.map(DrinkDraft.init) ?? DrinkDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        DrinkGlyph(category: draft.category, vessel: draft.vessel, volumeMl: draft.volumeMl)
                            .frame(height: 96)
                        Text("\(draft.units.unitsText) u · \(draft.kcal.kcalText) kcal")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Color.grog)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Name, e.g. Hepcat", text: $draft.name)
                        .font(.headline)
                    if drink?.isGeneric != true {
                        Toggle("Favourite", systemImage: "star", isOn: $draft.isFavourite)
                    }
                    ChipRow(options: DrinkCategory.allCases.filter { $0 != .units }, selection: category) { $0.label }
                    ChipRow(options: Vessel.allCases, selection: $draft.vessel) { $0.label }
                    ChipRow(options: draft.vessel.volumes, selection: $draft.volumeMl) { $0.volumeText }
                    NumberRow(label: "Volume", value: $draft.volumeMl, suffix: "ml")
                    NumberRow(label: "Strength", value: $draft.abv, suffix: "% ABV")
                    MoneyField(label: "Price", value: $draft.price, currency: prefs.currency)
                }

                if let drink {
                    Section {
                        Toggle("Show in picker", isOn: Binding(get: { !draft.isHidden }, set: { draft.isHidden = !$0 }))
                        if !drink.isGeneric {
                            Button("Delete drink", role: .destructive) {
                                context.delete(drink)
                                dismiss()
                            }
                        }
                    } footer: {
                        Text("Changes apply to drinks you log from now on. Past drinks keep what they were.")
                    }
                }
            }
            .animation(.snappy, value: draft.units)
            .navigationTitle(drink == nil ? "New drink" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(drink == nil ? "Add" : "Save", role: .confirm) {
                        if draft.name.isEmpty { draft.name = "\(draft.vessel.label) of \(draft.category.label.lowercased())" }
                        let target = drink ?? Drink(name: draft.name, category: draft.category, vessel: draft.vessel, volumeMl: draft.volumeMl, abv: draft.abv)
                        draft.apply(to: target)
                        if drink == nil { context.insert(target) }
                        dismiss()
                    }
                }
            }
        }
    }

    /// Changing the type on a new drink resets its serve to that type's usual one.
    private var category: Binding<DrinkCategory> {
        Binding(
            get: { draft.category },
            set: { category in
                draft.category = category
                guard drink == nil else { return }
                draft.vessel = category.defaultVessel
                draft.volumeMl = category.defaultVessel.volumes[0]
                draft.abv = category.defaultABV
            }
        )
    }
}

private struct DrinkDraft {
    var name = ""
    var category = DrinkCategory.beer
    var vessel = Vessel.pint
    var volumeMl = 568.0
    var abv = DrinkCategory.beer.defaultABV
    var price = 0.0
    var isFavourite = true
    var isHidden = false

    init() {}

    init(_ drink: Drink) {
        name = drink.name
        category = drink.category
        vessel = drink.vessel
        volumeMl = drink.volumeMl
        abv = drink.abv
        price = drink.price
        isFavourite = drink.isFavourite
        isHidden = drink.isHidden
    }

    var units: Double { Units.of(ml: volumeMl, abv: abv) }
    var kcal: Double { Units.kcal(ml: volumeMl, abv: abv, category: category) }

    func apply(to drink: Drink) {
        drink.name = name
        drink.category = category
        drink.vessel = vessel
        drink.volumeMl = volumeMl
        drink.abv = abv
        drink.price = price
        drink.isFavourite = isFavourite
        drink.isHidden = isHidden
    }
}

struct DrinksScreen: View {
    @Query(sort: \Drink.order) private var drinks: [Drink]
    @Environment(\.modelContext) private var context
    @State private var editing: Drink?
    @State private var creating = false

    var body: some View {
        List {
            section("Yours", drinks.filter { !$0.isGeneric })
            section("Generic", drinks.filter(\.isGeneric))
        }
        .navigationTitle("Drinks")
        .toolbar {
            Button("New drink", systemImage: "plus") { creating = true }
        }
        .sheet(item: $editing) { DrinkEditor(drink: $0) }
        .sheet(isPresented: $creating) { DrinkEditor(drink: nil) }
    }

    private func section(_ title: String, _ drinks: [Drink]) -> some View {
        Section(title) {
            ForEach(drinks) { drink in
                Button { editing = drink } label: {
                    HStack(spacing: 12) {
                        DrinkGlyph(category: drink.category, vessel: drink.vessel, volumeMl: drink.volumeMl)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading) {
                            Text(drink.name)
                            Text("\(drink.category.serving(ml: drink.volumeMl, abv: drink.abv)) · \(drink.units.unitsText) u")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if drink.isFavourite {
                            Image(systemName: "star.fill").foregroundStyle(Color.grog)
                        }
                        if drink.isHidden {
                            Image(systemName: "eye.slash").foregroundStyle(.secondary)
                        }
                    }
                    .opacity(drink.isHidden ? 0.5 : 1)
                }
                .tint(.primary)
                .swipeActions {
                    Button(drink.isHidden ? "Show" : "Hide", systemImage: drink.isHidden ? "eye" : "eye.slash") { drink.isHidden.toggle() }
                }
            }
            .onMove { from, to in
                var reordered = drinks
                reordered.move(fromOffsets: from, toOffset: to)
                for (index, drink) in reordered.enumerated() { drink.order = index + (drink.isGeneric ? 100 : 0) }
            }
        }
    }
}
