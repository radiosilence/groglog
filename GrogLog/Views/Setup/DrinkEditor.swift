import GRDBQuery
import SwiftUI

/// Create or edit a drink: what it is (name, type, strength), plus the size and price it's usually had at.
/// Sizes come from the type, so a beer is offered pints and cans, never a wine glass. Edits a draft saved on Save.
struct DrinkEditor: View {
    let drink: Drink?
    @Environment(\.databaseContext) private var database
    @Environment(\.dismiss) private var dismiss
    @Environment(Prefs.self) private var prefs
    @State private var draft: Drink
    @Query<PourCountRequest> private var timesLogged: Int

    init(drink: Drink?) {
        self.drink = drink
        _draft = State(initialValue: drink ?? Drink(name: "", category: .beer, abv: DrinkCategory.beer.defaultABV, vessel: .pint, volumeMl: 568))
        _timesLogged = Query(constant: PourCountRequest(drinkId: drink?.id ?? UUID()))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        DrinkGlyph(category: draft.category, vessel: draft.vessel, volumeMl: draft.volumeMl)
                            .frame(height: 96)
                        Text("\(Units.of(ml: draft.volumeMl, abv: draft.abv).unitsText) u · \(Units.kcal(ml: draft.volumeMl, abv: draft.abv, category: draft.category).kcalText) kcal")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Color.grog)
                            .contentTransition(.numericText())
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Name, e.g. Staropramen", text: $draft.name)
                        .font(.headline)
                    if drink?.isGeneric != true {
                        ChipRow(options: DrinkCategory.allCases.filter { $0 != .units }, selection: category) { $0.label }
                    }
                    NumberRow(label: "Strength", value: $draft.abv, suffix: "% ABV")
                }

                if draft.category != .units {
                    Section {
                        ChipRow(options: sizes, selection: size) { $0.vessel.label(ml: $0.ml) }
                        MoneyField(label: "Price", value: $draft.price, currency: prefs.currency)
                    } header: {
                        Text("Usual size")
                    } footer: {
                        Text("What it's first offered as. Long-press a tile to log it in another size.")
                    }
                }

                if let drink, !drink.isGeneric {
                    Section {
                        Button("Save as new drink", systemImage: "plus.square.on.square") {
                            var new = draft
                            new.id = UUID()
                            new.isGeneric = false
                            database.logbook(prefs).add(new)
                            dismiss()
                        }
                        Toggle("Show in pickers", isOn: Binding(get: { !draft.isHidden }, set: { draft.isHidden = !$0 }))
                        if timesLogged == 0 {
                            Button("Delete drink", role: .destructive) {
                                database.logbook(prefs).delete(drink)
                                dismiss()
                            }
                        }
                    } footer: {
                        Text("Saving updates everything logged as this drink. If the drink itself changed, save it as a new one and the old entries stay as they were.")
                    }
                }
            }
            .animation(.snappy, value: draft.abv)
            .navigationTitle(drink == nil ? "New drink" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(drink == nil ? "Add" : "Save", role: .confirm) {
                        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                        if drink == nil {
                            database.logbook(prefs).add(draft)
                        } else {
                            database.logbook(prefs).save(draft)
                        }
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var sizes: [Size] {
        let sizes = draft.category.serves.map { Size(vessel: $0.vessel, ml: $0.ml) }
        let current = Size(vessel: draft.vessel, ml: draft.volumeMl)
        return sizes.contains(current) ? sizes : sizes + [current]
    }

    private var size: Binding<Size> {
        Binding(get: { Size(vessel: draft.vessel, ml: draft.volumeMl) }, set: { draft.vessel = $0.vessel; draft.volumeMl = $0.ml })
    }

    /// Changing the type resets the size and, for a new drink, the strength to that type's usual.
    private var category: Binding<DrinkCategory> {
        Binding(
            get: { draft.category },
            set: { category in
                draft.category = category
                draft.vessel = category.serves[0].vessel
                draft.volumeMl = category.serves[0].ml
                if drink == nil { draft.abv = category.defaultABV }
            }
        )
    }
}

private struct Size: Hashable {
    let vessel: Vessel
    let ml: Double
}

struct DrinksScreen: View {
    @Query(DrinksRequest()) private var drinks: [Drink]
    @Environment(\.databaseContext) private var database
    @Environment(Prefs.self) private var prefs
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
                            Text(drink.category == .units ? "any amount" : "\(drink.category.label) · \(drink.abv.abvText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if drink.isHidden {
                            Image(systemName: "eye.slash").foregroundStyle(.secondary)
                        }
                    }
                    .opacity(drink.isHidden ? 0.5 : 1)
                }
                .tint(.primary)
                .swipeActions {
                    Button(drink.isHidden ? "Show" : "Hide", systemImage: drink.isHidden ? "eye" : "eye.slash") {
                        var toggled = drink
                        toggled.isHidden.toggle()
                        database.logbook(prefs).save(toggled)
                    }
                }
            }
        }
    }
}
