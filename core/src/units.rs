//! UK alcohol units and the energy in a drink.

const UNIT_ML: f64 = 10.0;
const WEEKLY_GUIDELINE: f64 = 14.0;
/// Ethanol is 0.789 g/ml, and Health's standard drink is 14 g of it.
const ETHANOL_G_PER_ML: f64 = 0.789;

/// UK units: 10 ml of pure alcohol.
#[uniffi::export]
pub fn units_of(ml: f64, abv: f64) -> f64 {
    ml * abv / 1000.0
}

/// Whether a typed strength is one a drink can have: above zero and at most pure alcohol.
#[uniffi::export]
pub fn units_is_strength(abv: f64) -> bool {
    abv > 0.0 && abv <= 100.0
}

/// Ethanol at 0.789 g/ml and 7 kcal/g, plus the drink's non-alcohol calories per ml.
#[uniffi::export]
pub fn units_kcal(ml: f64, abv: f64, other_kcal_per_ml: f64) -> f64 {
    ml * abv / 100.0 * ETHANOL_G_PER_ML * 7.0 + ml * other_kcal_per_ml
}

/// The UK Chief Medical Officers' low-risk weekly guideline.
#[uniffi::export]
pub fn units_weekly_guideline() -> f64 {
    WEEKLY_GUIDELINE
}

#[uniffi::export]
pub fn units_unit_ml() -> f64 {
    UNIT_ML
}

/// Health's standard drink: 14 g of alcohol, which is 17.7 ml, nearly two UK units.
#[uniffi::export]
pub fn units_standard_drink_ml() -> f64 {
    14.0 / ETHANOL_G_PER_ML
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pint_of_four_percent_is_about_two_units() {
        assert!((units_of(568.0, 4.0) - 2.272).abs() < 0.001);
    }

    #[test]
    fn calories_land_near_drinkaware() {
        assert!((units_kcal(568.0, 4.0, 0.10) - 182.0).abs() < 10.0);
        assert!((units_kcal(175.0, 13.0, 0.15) - 159.0).abs() < 10.0);
    }

    #[test]
    fn strengths_are_above_zero_and_at_most_pure() {
        assert!(!units_is_strength(0.0) && !units_is_strength(101.0) && units_is_strength(5.2) && units_is_strength(100.0));
    }
}
