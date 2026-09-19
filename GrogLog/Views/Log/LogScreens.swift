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

/// Edits a copy and writes it back on Done, so typing doesn't re-render every screen behind the sheet.
struct PourEditor: View {
    let pour: Pour
    let day: Date
    let clock: DayClock
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Prefs.self) private var prefs
    @State private var name: String
    @State private var time: Date
    @State private var volume: Double
    @State private var abv: Double
    @State private var price: Double

    init(pour: Pour, day: Date, clock: DayClock) {
        self.pour = pour
        self.day = day
        self.clock = clock
        _name = State(initialValue: pour.name)
        _time = State(initialValue: pour.timestamp)
        _volume = State(initialValue: pour.volumeMl)
        _abv = State(initialValue: pour.abv)
        _price = State(initialValue: pour.price)
    }

    var body: some View {
        let isUnits = pour.category == .units
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        DrinkGlyph(category: pour.category, vessel: pour.vessel, volumeMl: volume)
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading) {
                            TextField("Name", text: $name).font(.headline)
                            Text("\(Units.of(ml: volume, abv: abv).unitsText) u")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    DatePicker("Time", selection: Binding(get: { time }, set: { time = clock.resolve($0, into: day) }), displayedComponents: .hourAndMinute)
                    if isUnits {
                        NumberRow(label: "Units", value: Binding(get: { volume / 10 }, set: { volume = $0 * 10 }), suffix: "u")
                    } else {
                        NumberRow(label: "Volume", value: $volume, suffix: "ml")
                        NumberRow(label: "Strength", value: $abv, suffix: "% ABV")
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
                        let resized = volume != pour.volumeMl || abv != pour.abv
                        pour.name = name
                        pour.timestamp = time
                        pour.volumeMl = volume
                        pour.abv = abv
                        pour.price = price
                        if resized { pour.recalculateKcal() }
                        dismiss()
                    }
                }
            }
        }
    }
}
