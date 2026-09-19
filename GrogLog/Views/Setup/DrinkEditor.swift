import SwiftData
import SwiftUI

/// Create or edit a drink. Picking a type fills in a sensible vessel, size and strength, so a new drink is usually type → name → done.
struct DrinkEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Prefs.self) private var prefs
    @State private var draft: Drink
    private let isNew: Bool

    init(drink: Drink?) {
        isNew = drink == nil
        _draft = State(initialValue: drink ?? Drink(name: "", category: .beer, vessel: .pint, volumeMl: 568, abv: DrinkCategory.beer.defaultABV, isFavourite: true))
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
                    if !draft.isGeneric {
                        Toggle("Favourite", systemImage: "star", isOn: $draft.isFavourite)
                    }
                    ChipRow(options: DrinkCategory.allCases.filter { $0 != .units }, selection: category) { $0.label }
                    ChipRow(options: Vessel.allCases, selection: $draft.vessel) { $0.label }
                    ChipRow(options: draft.vessel.volumes, selection: $draft.volumeMl) { $0.volumeText }
                    NumberRow(label: "Volume", value: $draft.volumeMl, suffix: "ml")
                    NumberRow(label: "Strength", value: $draft.abv, suffix: "% ABV")
                    LabeledContent("Price") {
                        TextField("Price", value: $draft.price, format: .currency(code: prefs.currency))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                }

                if !isNew {
                    Section {
                        Button(draft.isHidden ? "Show in picker" : "Hide from picker") { draft.isHidden.toggle() }
                        if !draft.isGeneric {
                            Button("Delete drink", role: .destructive) {
                                context.delete(draft)
                                dismiss()
                            }
                        }
                    } footer: {
                        Text("Changes apply to drinks you log from now on. Past drinks keep what they were.")
                    }
                }
            }
            .animation(.snappy, value: draft.units)
            .navigationTitle(isNew ? "New drink" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isNew {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Done", role: .confirm) {
                        if isNew {
                            if draft.name.isEmpty { draft.name = "\(draft.vessel.label) of \(draft.category.label.lowercased())" }
                            context.insert(draft)
                        }
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
                guard isNew else { return }
                draft.vessel = category.defaultVessel
                draft.volumeMl = category.defaultVessel.volumes[0]
                draft.abv = category.defaultABV
            }
        )
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
