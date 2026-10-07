import GRDBQuery
import SwiftUI

/// The Log tab: today's drink picker, front and centre.
struct LogScreen: View {
    let ledger: Ledger

    var body: some View {
        DrinkPicker(day: ledger.today, ledger: ledger)
            .navigationTitle("Log")
            .background(Color(.systemGroupedBackground))
    }
}

/// The picker for backfilling another day.
struct AddDrinkSheet: View {
    let day: DayKey
    @Environment(Prefs.self) private var prefs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LedgerReader { ledger in
                DrinkPicker(day: day, ledger: ledger)
            }
            .navigationTitle(day.date(in: prefs.clock.calendar).formatted(.dateTime.weekday(.wide).day().month()))
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
    let entry: Entry
    let day: DayKey
    @Environment(\.databaseContext) private var database
    @Environment(\.dismiss) private var dismiss
    @Environment(Prefs.self) private var prefs
    @State private var time: Date
    @State private var vessel: Vessel
    @State private var volume: Double
    @State private var price: Double
    @State private var abv: Double
    @State private var editingDrink = false

    init(entry: Entry, day: DayKey) {
        self.entry = entry
        self.day = day
        _time = State(initialValue: entry.timestamp)
        _vessel = State(initialValue: entry.vessel)
        _volume = State(initialValue: entry.volumeMl)
        _price = State(initialValue: entry.price)
        _abv = State(initialValue: entry.abv)
    }

    var body: some View {
        let isUnits = entry.category == .units
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        DrinkGlyph(category: entry.category, vessel: vessel, volumeMl: volume)
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading) {
                            Text(entry.name).font(.headline)
                            Text("\(Units.of(ml: volume, abv: abv).unitsText) u")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !isUnits {
                        Button("Edit \(entry.name)", systemImage: "pencil") { editingDrink = true }
                    }
                }
                Section {
                    DatePicker("Time", selection: Binding(get: { time }, set: { time = prefs.clock.resolve($0, into: day) }), displayedComponents: .hourAndMinute)
                    if isUnits {
                        NumberRow(label: "Units", value: Binding(get: { volume / 10 }, set: { volume = $0 * 10 }), suffix: "u")
                    } else {
                        let size = ServeSize(vessel, volume)
                        ChipRow(options: entry.drink.sizes(including: size), selection: Binding(get: { size }, set: { vessel = $0.vessel; volume = $0.ml })) { $0.label }
                        NumberRow(label: "Size", value: $volume, suffix: "ml")
                        NumberRow(label: "Strength", value: $abv, suffix: "% ABV")
                    }
                    MoneyField(label: "Price", value: $price, currency: prefs.currency)
                }
                Section {
                    Button("Delete", role: .destructive) {
                        database.logbook(prefs).delete(entry.pour)
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
                        database.logbook(prefs).update(entry.pour, time: time, vessel: vessel, volumeMl: volume, price: price, abvOverride: isUnits || abv == entry.drink.abv ? nil : abv)
                        dismiss()
                    }
                    .disabled(!isUnits && !Units.isStrength(abv))
                }
            }
            .sheet(isPresented: $editingDrink) { DrinkEditor(drink: entry.drink) }
        }
    }
}
