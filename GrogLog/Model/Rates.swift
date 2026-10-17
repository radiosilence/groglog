import Foundation
import GrogLogCore

/// The currencies prices can be shown in. The rates behind them are in the shared core.
nonisolated enum Rates {
    /// The three original currencies come first; the rest are alphabetical.
    static let currencies: [String] = ratesCurrencies()
}
