import Foundation
import GrogLogCore

/// What a pound buys in each currency, for pricing a drink from one market in another's currency. The table is in
/// the shared core.
nonisolated enum Rates {
    static let asOf = ratesAsOf()

    static let perPound: [String: Double] = Dictionary(uniqueKeysWithValues: ratesPerPound().map { ($0.currency, $0.perPound) })

    /// The three original currencies come first; the rest are alphabetical.
    static let currencies: [String] = ratesCurrencies()

    static func convert(_ amount: Double, from: String, to: String) -> Double? {
        ratesConvert(amount: amount, from: from, to: to)
    }
}
