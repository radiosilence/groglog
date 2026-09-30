import SwiftUI

/// A row of pill buttons for picking one of a few values.
struct ChipRow<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    /// An option that isn't on offer stays on the row, greyed. Withdrawing it outright leaves a gap
    /// that reads as a missing feature rather than a decision, and there's no telling what was there.
    var isEnabled: (Value) -> Bool = { _ in true }
    let label: (Value) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button(label(option)) { selection = option }
                        .buttonStyle(.bordered)
                        .tint(option == selection ? .grog : .secondary)
                        .fontWeight(option == selection ? .semibold : .regular)
                        .disabled(!isEnabled(option))
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
    /// Called when the field is done being typed into. Anything that reacts to the value by changing
    /// something else belongs here rather than on the value itself — halfway through typing "30" the
    /// value is 3, and acting on that fights whoever is typing.
    var onEditingEnded: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(label, value: $value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .keypadDone($focused)
                    .onChange(of: focused) { was, now in if was && !now { onEditingEnded() } }
                Text(suffix).foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    /// Number pads have no return key, so a field using one needs its own way out.
    /// Gated on focus so only the field being typed into puts a button up.
    func keypadDone(_ focused: FocusState<Bool>.Binding) -> some View {
        toolbar {
            if focused.wrappedValue {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused.wrappedValue = false }
                }
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

    /// Digits per whole unit of the currency: 100 for pence and cents, 1 for yen and won, which have no minor unit.
    private var scale: Double {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return pow(10, Double(formatter.maximumFractionDigits))
    }

    var body: some View {
        LabeledContent(label) {
            Text((Double(Int(digits) ?? 0) / scale).money(currency))
                .monospacedDigit()
                .foregroundStyle(focused ? Color.grog : .primary)
                .background {
                    TextField(label, text: $digits)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .keypadDone($focused)
                        .opacity(0)
                }
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
        .onAppear { digits = String(Int((value * scale).rounded())) }
        .onChange(of: digits) {
            let clean = String(digits.filter(\.isNumber).prefix(9))
            if clean != digits { digits = clean }
            value = Double(Int(clean) ?? 0) / scale
        }
    }
}
