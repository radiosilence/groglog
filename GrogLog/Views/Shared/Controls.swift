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

/// Money entered like a banking app: digits only, filling from the pence up — typing 1, 5, 0 reads £0.01, £0.15, £1.50.
/// A hidden digits field takes the keystrokes; the label shows them as money.
struct MoneyField: View {
    let label: String
    @Binding var value: Double
    let currency: String
    @State private var digits = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(label) {
            Text((Double(Int(digits) ?? 0) / 100).money(currency))
                .monospacedDigit()
                .foregroundStyle(focused ? Color.grog : .primary)
                .background {
                    TextField(label, text: $digits)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .opacity(0)
                }
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .onAppear { digits = String(Int((value * 100).rounded())) }
        .onChange(of: digits) {
            let clean = String(digits.filter(\.isNumber).prefix(9))
            if clean != digits { digits = clean }
            value = Double(Int(clean) ?? 0) / 100
        }
    }
}
