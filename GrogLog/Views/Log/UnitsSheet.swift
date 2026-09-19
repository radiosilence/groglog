import SwiftData
import SwiftUI

/// Log a bare number of units — for when you know the total but not the drinks.
struct UnitsSheet: View {
    let day: Date
    let ledger: Ledger
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var units: Double?
    @State private var time: Date
    @FocusState private var focused: Bool

    init(day: Date, ledger: Ledger) {
        self.day = day
        self.ledger = ledger
        _time = State(initialValue: ledger.clock.suggestedTime(for: day, after: ledger.pours(on: day).last?.timestamp))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        TextField("0", value: $units, format: .number)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .keyboardType(.decimalPad)
                            .focused($focused)
                        Text("units").font(.title2).foregroundStyle(.secondary)
                    }
                }
                Section {
                    DatePicker("At", selection: Binding(get: { time }, set: { time = ledger.clock.resolve($0, into: day) }), displayedComponents: .hourAndMinute)
                } footer: {
                    Text("Counts towards the day like any drink. Use it for totals from another app, or a night you didn't log drink by drink.")
                }
            }
            .navigationTitle("Units")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log", role: .confirm) {
                        guard let units, units > 0 else { return }
                        context.insert(Pour(drink: context.unitsDrink(), at: time, volumeMl: units * 10))
                        context.setAlcoholFree(false, on: day)
                        dismiss()
                    }
                    .disabled((units ?? 0) <= 0)
                }
            }
        }
    }
}
