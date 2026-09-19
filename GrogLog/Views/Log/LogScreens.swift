import SwiftData
import SwiftUI

/// The Log tab: today's drink picker, front and centre.
struct LogScreen: View {
    let ledger: Ledger

    var body: some View {
        DrinkPicker(day: ledger.clock.today, ledger: ledger)
            .navigationTitle("Log")
            .background(Color(.systemGroupedBackground))
    }
}

/// The picker for backfilling another day.
struct AddDrinkSheet: View {
    let day: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LedgerReader { ledger in
                DrinkPicker(day: day, ledger: ledger)
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
    }
}

/// One logged drink: when, how much, what it cost. Name and strength belong to the drink, edited from here via its own editor.
/// Works on a draft saved on Done.
struct PourEditor: View {
    let pour: Pour
    let day: Date
    let clock: DayClock
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Prefs.self) private var prefs
    @State private var time: Date
    @State private var vessel: Vessel
    @State private var volume: Double
    @State private var price: Double
    @State private var editingDrink = false

    init(pour: Pour, day: Date, clock: DayClock) {
        self.pour = pour
        self.day = day
        self.clock = clock
        _time = State(initialValue: pour.timestamp)
        _vessel = State(initialValue: pour.vessel)
        _volume = State(initialValue: pour.volumeMl)
        _price = State(initialValue: pour.price)
    }

    var body: some View {
        let isUnits = pour.category == .units
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        DrinkGlyph(category: pour.category, vessel: vessel, volumeMl: volume)
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading) {
                            Text(pour.name).font(.headline)
                            Text("\(Units.of(ml: volume, abv: pour.abv).unitsText) u")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let drink = pour.drink, !isUnits {
                        Button("Edit \(drink.name)", systemImage: "pencil") { editingDrink = true }
                    }
                }
                Section {
                    DatePicker("Time", selection: Binding(get: { time }, set: { time = clock.resolve($0, into: day) }), displayedComponents: .hourAndMinute)
                    if isUnits {
                        NumberRow(label: "Units", value: Binding(get: { volume / 10 }, set: { volume = $0 * 10 }), suffix: "u")
                    } else {
                        let sizes = pour.category.serves.map { Size(vessel: $0.vessel, ml: $0.ml) }
                        ChipRow(options: sizes.contains(Size(vessel: vessel, ml: volume)) ? sizes : sizes + [Size(vessel: vessel, ml: volume)],
                                selection: Binding(get: { Size(vessel: vessel, ml: volume) }, set: { vessel = $0.vessel; volume = $0.ml })) {
                            $0.vessel.label(ml: $0.ml)
                        }
                        NumberRow(label: "Size", value: $volume, suffix: "ml")
                    }
                    MoneyField(label: "Price", value: $price, currency: prefs.currency)
                }
                Section {
                    Button("Delete", role: .destructive) {
                        context.delete(pour)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) {
                        pour.timestamp = time
                        pour.vesselRaw = vessel.rawValue
                        pour.volumeMl = volume
                        pour.price = price
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $editingDrink) {
                if let drink = pour.drink { DrinkEditor(drink: drink) }
            }
        }
    }
}

private struct Size: Hashable {
    let vessel: Vessel
    let ml: Double
}
