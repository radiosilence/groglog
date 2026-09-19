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

struct PourEditor: View {
    @Bindable var pour: Pour
    let day: Date
    let clock: DayClock
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Prefs.self) private var prefs

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        DrinkGlyph(category: pour.category, vessel: pour.vessel, volumeMl: pour.volumeMl)
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading) {
                            TextField("Name", text: $pour.name).font(.headline)
                            Text("\(pour.units.unitsText) u · \(pour.kcal.kcalText) kcal")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    DatePicker("Time", selection: Binding(get: { pour.timestamp }, set: { pour.timestamp = clock.resolve($0, into: day) }), displayedComponents: .hourAndMinute)
                    NumberRow(label: "Volume", value: $pour.volumeMl, suffix: "ml")
                    NumberRow(label: "Strength", value: $pour.abv, suffix: "% ABV")
                    LabeledContent("Price") {
                        TextField("Price", value: $pour.price, format: .currency(code: prefs.currency))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                    }
                }
                Section {
                    Button("Delete", role: .destructive) {
                        context.delete(pour)
                        dismiss()
                    }
                }
            }
            .onChange(of: pour.volumeMl) { pour.recalculateKcal() }
            .onChange(of: pour.abv) { pour.recalculateKcal() }
            .navigationTitle("Drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) { dismiss() }
                }
            }
        }
    }
}

/// A labelled decimal field with a unit suffix.
struct NumberRow: View {
    let label: String
    @Binding var value: Double
    let suffix: String

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(label, value: $value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                Text(suffix).foregroundStyle(.secondary)
            }
        }
    }
}
