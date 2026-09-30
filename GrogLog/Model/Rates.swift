import Foundation

/// What a pound buys in each currency, for pricing a drink from one market in another's currency.
///
/// A dated snapshot of the ECB's reference rates. A catalogue price is only a starting point that the user owns
/// once copied in, so it does not justify requiring a network connection. A drink priced in the user's own
/// currency is never converted.
nonisolated enum Rates {
    static let asOf = "2026-09-25"

    /// The three original currencies come first; the rest are alphabetical.
    static let perPound: [String: Double] = [
        "GBP": 1,
        "EUR": 1.16218,
        "USD": 1.32524,
        "AUD": 1.88506,
        "BRL": 6.86745,
        "CAD": 1.87425,
        "CHF": 1.09768,
        "CNY": 8.89662,
        "CZK": 28.2933,
        "DKK": 8.6879,
        "HKD": 10.3951,
        "HUF": 424.522,
        "IDR": 23740.2,
        "ILS": 4.02045,
        "INR": 126.981,
        "ISK": 158.754,
        "JPY": 208.844,
        "KRW": 1795.76,
        "MXN": 23.4547,
        "MYR": 5.39904,
        "NOK": 12.5981,
        "NZD": 2.33692,
        "PHP": 82.7985,
        "PLN": 5.08083,
        "RON": 6.13226,
        "SEK": 13.121,
        "SGD": 1.69249,
        "THB": 44.1897,
        "TRY": 64.8469,
        "ZAR": 21.5931,
    ]

    static let currencies: [String] = ["GBP", "EUR", "USD"] + perPound.keys.filter { !["GBP", "EUR", "USD"].contains($0) }.sorted()

    static func convert(_ amount: Double, from: String, to: String) -> Double? {
        if from == to { return amount }
        guard let source = perPound[from], let target = perPound[to] else { return nil }
        return amount / source * target
    }
}
