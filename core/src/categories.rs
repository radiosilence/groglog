//! The kinds of drink and the vessels they come in, by the names the database and the backup format store.

pub const CATEGORIES: [&str; 12] = [
    "beer", "stout", "cider", "redWine", "whiteWine", "rose", "bubbles", "spirit", "alcopop", "cocktail", "fortified", "units",
];

pub const VESSELS: [&str; 10] = ["pint", "half", "can", "bottle", "wineBottle", "wineGlass", "flute", "shot", "tumbler", "coupe"];

pub fn is_category(name: &str) -> bool {
    CATEGORIES.contains(&name)
}

pub fn is_vessel(name: &str) -> bool {
    VESSELS.contains(&name)
}

/// Drinkaware's standard strengths, used for the generic drinks.
pub fn default_abv(category: &str) -> f64 {
    match category {
        "beer" | "stout" => 4.0,
        "cider" => 4.5,
        "redWine" | "whiteWine" | "rose" | "bubbles" => 12.0,
        "spirit" => 40.0,
        "alcopop" => 5.0,
        "cocktail" => 15.0,
        "fortified" => 20.0,
        _ => 100.0,
    }
}

pub fn default_vessel(category: &str) -> &'static str {
    match category {
        "beer" | "stout" | "cider" => "pint",
        "redWine" | "whiteWine" | "rose" | "fortified" => "wineGlass",
        "bubbles" => "flute",
        "alcopop" => "bottle",
        "cocktail" => "coupe",
        _ => "shot",
    }
}

#[uniffi::export]
pub fn category_default_abv(category: String) -> f64 {
    default_abv(&category)
}

#[uniffi::export]
pub fn category_default_vessel(category: String) -> String {
    default_vessel(&category).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_category_has_a_vessel_and_a_strength() {
        for category in CATEGORIES {
            assert!(is_vessel(default_vessel(category)), "{category}");
            assert!(default_abv(category) > 0.0, "{category}");
        }
        assert_eq!((default_vessel("redWine"), default_abv("fortified")), ("wineGlass", 20.0));
        assert_eq!((default_vessel("units"), default_abv("units")), ("shot", 100.0));
    }
}
