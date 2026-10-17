//! What a pound buys in each currency, for pricing a drink from one market in another's currency.
//!
//! A dated snapshot of the ECB's reference rates. A catalogue price is only a starting point that the user owns once
//! copied in, so it does not justify requiring a network connection. A drink priced in the user's own currency is never
//! converted.

pub(crate) const AS_OF: &str = "2026-09-25";

/// The three original currencies come first; the rest are alphabetical.
pub(crate) static PER_POUND: &[(&str, f64)] = &[
    ("GBP", 1.0),
    ("EUR", 1.16218),
    ("USD", 1.32524),
    ("AUD", 1.88506),
    ("BRL", 6.86745),
    ("CAD", 1.87425),
    ("CHF", 1.09768),
    ("CNY", 8.89662),
    ("CZK", 28.2933),
    ("DKK", 8.6879),
    ("HKD", 10.3951),
    ("HUF", 424.522),
    ("IDR", 23740.2),
    ("ILS", 4.02045),
    ("INR", 126.981),
    ("ISK", 158.754),
    ("JPY", 208.844),
    ("KRW", 1795.76),
    ("MXN", 23.4547),
    ("MYR", 5.39904),
    ("NOK", 12.5981),
    ("NZD", 2.33692),
    ("PHP", 82.7985),
    ("PLN", 5.08083),
    ("RON", 6.13226),
    ("SEK", 13.121),
    ("SGD", 1.69249),
    ("THB", 44.1897),
    ("TRY", 64.8469),
    ("ZAR", 21.5931),
];

pub(crate) fn per_pound(currency: &str) -> Option<f64> {
    PER_POUND.iter().find(|(code, _)| *code == currency).map(|(_, rate)| *rate)
}

pub(crate) fn convert(amount: f64, from: &str, to: &str) -> Option<f64> {
    if from == to {
        return Some(amount);
    }
    Some(amount / per_pound(from)? * per_pound(to)?)
}

/// The currencies on offer: pounds, euros and dollars, then the rest by code.
pub(crate) fn currencies() -> Vec<&'static str> {
    let first = ["GBP", "EUR", "USD"];
    let mut rest: Vec<&str> = PER_POUND.iter().map(|(code, _)| *code).filter(|code| !first.contains(code)).collect();
    rest.sort_unstable();
    first.into_iter().chain(rest).collect()
}

#[uniffi::export]
pub fn rates_as_of() -> String {
    AS_OF.to_string()
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RateRecord {
    pub currency: String,
    pub per_pound: f64,
}

/// Every currency with what a pound buys, in the order the table gives them.
#[uniffi::export]
pub fn rates_per_pound() -> Vec<RateRecord> {
    PER_POUND.iter().map(|(currency, per_pound)| RateRecord { currency: currency.to_string(), per_pound: *per_pound }).collect()
}

#[uniffi::export]
pub fn rates_currencies() -> Vec<String> {
    currencies().into_iter().map(String::from).collect()
}

#[uniffi::export]
pub fn rates_convert(amount: f64, from: String, to: String) -> Option<f64> {
    convert(amount, &from, &to)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_through_pounds_and_refuses_unknown_currencies() {
        assert_eq!(convert(5.0, "GBP", "GBP"), Some(5.0));
        assert!((convert(10.0, "GBP", "EUR").unwrap() - 11.6218).abs() < 1e-9);
        assert!((convert(11.6218, "EUR", "GBP").unwrap() - 10.0).abs() < 1e-9);
        assert_eq!(convert(1.0, "GBP", "XXX"), None);
        assert_eq!(convert(1.0, "XXX", "XXX"), Some(1.0));
    }

    #[test]
    fn the_three_original_currencies_come_first() {
        let all = currencies();
        assert_eq!(&all[..3], ["GBP", "EUR", "USD"]);
        assert!(all[3..].windows(2).all(|pair| pair[0] < pair[1]));
        assert_eq!(all.len(), PER_POUND.len());
    }
}
