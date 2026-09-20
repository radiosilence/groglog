import GRDBQuery
import SwiftUI

extension Color {
    static let grog = Color(red: 0.97, green: 0.64, blue: 0.20)
    static let dry = Color(red: 0.20, green: 0.74, blue: 0.60)
    static let over = Color(red: 0.88, green: 0.24, blue: 0.30)

    /// Teal for a day inside its budget, amber just over, sliding to red the further past it goes.
    static func heat(units: Double, budget: Double?) -> Color {
        let limit = budget ?? Units.weeklyGuideline / 7
        guard units > limit else { return .dry }
        return Color.grog.mix(with: .over, by: min(1, (units - limit) / limit))
    }
}

nonisolated extension Double {
    var unitsText: String { formatted(.number.precision(.fractionLength(1))) }
    var kcalText: String { Int(rounded()).formatted() }
    func money(_ currency: String) -> String { formatted(.currency(code: currency)) }
    var volumeText: String { "\(Int(self)) ml" }
    var abvText: String { "\(formatted(.number.precision(.fractionLength(0...1))))%" }
}

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }
}

/// Builds a `Ledger` from the per-day totals — never the individual drinks — so it stays cheap however long the history.
struct LedgerReader<Content: View>: View {
    @Query(DaysRequest()) private var days: [Day]
    @Environment(Prefs.self) private var prefs
    @ViewBuilder var content: (Ledger) -> Content

    var body: some View {
        content(Ledger(days: days, clock: prefs.clock))
    }
}

/// A series swatch for chart legends.
struct LegendKey: View {
    let label: String
    let color: Color
    var dashed = false
    /// A filled swatch for a series drawn as bars, so the key looks like the thing it labels.
    var bar = false
    /// Where the bars are coloured by how far over budget they are, the swatch carries the whole scale.
    var ramp: [Color] = []

    var body: some View {
        HStack(spacing: 6) {
            if bar {
                RoundedRectangle(cornerRadius: 2)
                    .fill(ramp.isEmpty ? AnyShapeStyle(color) : AnyShapeStyle(LinearGradient(colors: ramp, startPoint: .bottom, endPoint: .top)))
                    .frame(width: 9, height: 12)
            } else {
                Capsule()
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: dashed ? [3, 4] : []))
                    .frame(width: 18, height: 1)
            }
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
