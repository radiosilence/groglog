import SwiftData
import SwiftUI

/// Log a bare number of units — for when you know the total but not the drinks.
struct UnitsSheet: View {
    let day: DayKey
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Prefs.self) private var prefs
    @State private var units: Double?
    @State private var time: Date
    @FocusState private var focused: Bool

    init(day: DayKey, at time: Date) {
        self.day = day
        _time = State(initialValue: time)
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
                    DatePicker("At", selection: Binding(get: { time }, set: { time = prefs.clock.resolve($0, into: day) }), displayedComponents: .hourAndMinute)
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
                        context.logbook(prefs).logUnits(units, at: time)
                        dismiss()
                    }
                    .disabled((units ?? 0) <= 0)
                }
            }
        }
    }
}
