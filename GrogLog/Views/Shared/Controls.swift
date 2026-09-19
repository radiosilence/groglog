import SwiftUI

/// A row of pill buttons for picking one of a few values.
struct ChipRow<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button(label(option)) { selection = option }
                        .buttonStyle(.bordered)
                        .tint(option == selection ? .grog : .secondary)
                        .fontWeight(option == selection ? .semibold : .regular)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
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

/// Money entered like a banking app: digits only, filling from the pence up — typing 1, 6, 0 reads £0.01, £0.16, £1.60.
struct MoneyField: View {
    let label: String
    @Binding var value: Double
    let currency: String

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: Binding(
                get: { value.money(currency) },
                set: { value = Double(Int(String($0.filter(\.isNumber).prefix(9))) ?? 0) / 100 }
            ))
            .multilineTextAlignment(.trailing)
            .keyboardType(.numberPad)
            .monospacedDigit()
        }
    }
}
