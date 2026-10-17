//! The rules the log follows whenever it changes: how a day's row is derived from its drinks, when a row is removed,
//! how everything is rebuilt, and which prices a reset changes. The apps keep the transactions and the storage; they
//! read what the rules need, ask here what to write, and write it.

use std::collections::{BTreeMap, HashMap, HashSet};

use crate::catalog::catalog_price;
use crate::categories::{CategoryKind, VesselKind};
use crate::ledger::DayRow;

/// One drink's contribution to its day.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct PourTotals {
    pub units: f64,
    pub kcal: f64,
    pub price: f64,
}

/// A drink with the day it counted towards, for rebuilding every day at once.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct DayPour {
    pub day: i64,
    pub units: f64,
    pub kcal: f64,
    pub price: f64,
}

/// What to do with a day's row after its drinks changed: write `row`, or remove it when `delete` is set.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct RetotalRow {
    pub row: DayRow,
    pub delete: bool,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RebuildPlan {
    pub updates: Vec<DayRow>,
    pub deletes: Vec<i64>,
    pub inserts: Vec<DayRow>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct DrinkPriceIn {
    pub id: String,
    pub name: String,
    pub category: CategoryKind,
    pub vessel: VesselKind,
    pub volume_ml: f64,
    pub price: f64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FavouritePriceIn {
    pub id: String,
    pub drink_id: String,
    pub vessel: VesselKind,
    pub volume_ml: f64,
    pub price: f64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PriceChange {
    pub id: String,
    pub price: f64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PriceResets {
    pub drinks: Vec<PriceChange>,
    pub favourites: Vec<PriceChange>,
}

/// A day's row with nothing on it.
fn blank(number: i64) -> DayRow {
    DayRow { number, is_alcohol_free: false, units: 0.0, kcal: 0.0, cost: 0.0, count: 0, cost_override: None }
}

/// A day with neither drinks, a dry mark nor a hand-set spend has no row.
fn is_empty(row: &DayRow) -> bool {
    row.count == 0 && !row.is_alcohol_free && row.cost_override.is_none()
}

fn set_totals(row: &mut DayRow, units: f64, kcal: f64, cost: f64, count: i64) {
    row.units = units;
    row.kcal = kcal;
    row.cost = cost;
    row.count = count;
}

/// Recomputes a day's row from its drinks. Totals are derived, never incremented, so a row cannot drift from its
/// drinks. Logging a drink clears a dry mark; a day left with nothing is removed.
#[uniffi::export]
pub fn logbook_retotal(existing: Option<DayRow>, day: i64, pours: Vec<PourTotals>) -> RetotalRow {
    let mut row = existing.unwrap_or_else(|| blank(day));
    set_totals(
        &mut row,
        pours.iter().map(|p| p.units).sum(),
        pours.iter().map(|p| p.kcal).sum(),
        pours.iter().map(|p| p.price).sum(),
        pours.len() as i64,
    );
    if !pours.is_empty() {
        row.is_alcohol_free = false;
    }
    RetotalRow { row, delete: is_empty(&row) }
}

/// What to do with a day's row after the app edited it directly (a dry mark or a hand-set spend): write it, or remove
/// it if the edit left nothing on it.
#[uniffi::export]
pub fn logbook_day_after_edit(row: DayRow) -> RetotalRow {
    RetotalRow { row, delete: is_empty(&row) }
}

/// Recomputes every day after an import or when the day-end hour changes. Existing rows are rewritten in place rather
/// than deleted and reinserted, which would resend every dry mark and manual spend from every device; a row left empty
/// is removed, and a day with drinks and no row gets one.
#[uniffi::export]
pub fn logbook_rebuild(existing: Vec<DayRow>, pours: Vec<DayPour>) -> RebuildPlan {
    let mut totals: BTreeMap<i64, (f64, f64, f64, i64)> = BTreeMap::new();
    for pour in &pours {
        let entry = totals.entry(pour.day).or_insert((0.0, 0.0, 0.0, 0));
        entry.0 += pour.units;
        entry.1 += pour.kcal;
        entry.2 += pour.price;
        entry.3 += 1;
    }
    let mut plan = RebuildPlan { updates: Vec::new(), deletes: Vec::new(), inserts: Vec::new() };
    for mut row in existing.iter().copied() {
        let (units, kcal, cost, count) = totals.get(&row.number).copied().unwrap_or((0.0, 0.0, 0.0, 0));
        set_totals(&mut row, units, kcal, cost, count);
        if is_empty(&row) { plan.deletes.push(row.number) } else { plan.updates.push(row) }
    }
    let known: HashSet<i64> = existing.iter().map(|row| row.number).collect();
    for (number, (units, kcal, cost, count)) in totals {
        if !known.contains(&number) {
            let mut row = blank(number);
            set_totals(&mut row, units, kcal, cost, count);
            plan.inserts.push(row);
        }
    }
    plan
}

/// A drink logged at the strength its drink already has needs no override of its own.
#[uniffi::export]
pub fn logbook_abv_override(drink_abv: f64, abv: Option<f64>) -> Option<f64> {
    abv.filter(|abv| *abv != drink_abv)
}

/// Whether editing a drink changes what it was logged as, so every day it appears on has to be recomputed.
#[uniffi::export]
pub fn logbook_drink_edit_retotals(before_abv: f64, before_category: CategoryKind, after_abv: f64, after_category: CategoryKind) -> bool {
    before_abv != after_abv || before_category != after_category
}

/// The catalogue price for every drink and Log tile whose price has drifted. Drinks the catalogue does not price are
/// left alone, and logged entries keep the price recorded at the time.
#[uniffi::export]
pub fn logbook_price_resets(drinks: Vec<DrinkPriceIn>, favourites: Vec<FavouritePriceIn>, currency: String) -> PriceResets {
    let reset = |drink: &DrinkPriceIn, vessel: VesselKind, volume_ml: f64, price: f64| {
        catalog_price(drink.name.clone(), drink.category, vessel, volume_ml, currency.clone()).filter(|listed| *listed != price)
    };
    let by_id: HashMap<&str, &DrinkPriceIn> = drinks.iter().map(|drink| (drink.id.as_str(), drink)).collect();
    PriceResets {
        drinks: drinks
            .iter()
            .filter_map(|drink| reset(drink, drink.vessel, drink.volume_ml, drink.price).map(|price| PriceChange { id: drink.id.clone(), price }))
            .collect(),
        favourites: favourites
            .iter()
            .filter_map(|favourite| {
                let drink = by_id.get(favourite.drink_id.as_str())?;
                reset(drink, favourite.vessel, favourite.volume_ml, favourite.price).map(|price| PriceChange { id: favourite.id.clone(), price })
            })
            .collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pour(units: f64) -> PourTotals {
        PourTotals { units, kcal: units * 60.0, price: units * 2.0 }
    }

    #[test]
    fn a_days_row_is_derived_from_its_drinks() {
        let result = logbook_retotal(None, 5, vec![pour(2.0), pour(1.5)]);
        assert_eq!((result.row.units, result.row.kcal, result.row.cost, result.row.count), (3.5, 210.0, 7.0, 2));
        assert!(!result.delete);
    }

    #[test]
    fn logging_clears_a_dry_mark_and_an_empty_day_disappears() {
        let dry = DayRow { is_alcohol_free: true, ..blank(5) };
        assert!(!logbook_retotal(Some(dry), 5, vec![pour(1.0)]).row.is_alcohol_free);
        // Removing the last drink leaves a day with nothing on it.
        let after_undo = logbook_retotal(Some(DayRow { count: 1, units: 1.0, ..blank(5) }), 5, vec![]);
        assert!(after_undo.delete && after_undo.row.count == 0);
        // A dry mark or a hand-set spend keeps the row.
        assert!(!logbook_retotal(Some(dry), 5, vec![]).delete);
        assert!(!logbook_retotal(Some(DayRow { cost_override: Some(9.0), ..blank(5) }), 5, vec![]).delete);
    }

    #[test]
    fn clearing_the_last_thing_on_a_day_removes_its_row() {
        assert!(logbook_day_after_edit(blank(5)).delete);
        assert!(!logbook_day_after_edit(DayRow { is_alcohol_free: true, ..blank(5) }).delete);
        assert!(!logbook_day_after_edit(DayRow { cost_override: Some(0.0), ..blank(5) }).delete);
        assert!(!logbook_day_after_edit(DayRow { count: 1, ..blank(5) }).delete);
    }

    #[test]
    fn a_spend_on_its_own_survives_the_drinks_coming_and_going() {
        let result = logbook_retotal(Some(DayRow { cost_override: Some(12.0), ..blank(5) }), 5, vec![pour(1.0)]);
        assert_eq!(result.row.cost_override, Some(12.0));
        assert_eq!(result.row.cost, 2.0, "the sum of prices is kept alongside it");
    }

    #[test]
    fn a_rebuild_rewrites_rows_in_place_and_adds_the_missing_ones() {
        let stale = DayRow { units: 99.0, count: 3, ..blank(1) };
        let dry = DayRow { is_alcohol_free: true, units: 4.0, count: 1, ..blank(2) };
        let gone = DayRow { units: 1.0, count: 1, ..blank(3) };
        let pours = vec![
            DayPour { day: 1, units: 2.0, kcal: 100.0, price: 4.0 },
            DayPour { day: 2, units: 1.0, kcal: 50.0, price: 2.0 },
            DayPour { day: 7, units: 3.0, kcal: 150.0, price: 6.0 },
        ];
        let plan = logbook_rebuild(vec![stale, dry, gone], pours);
        assert_eq!(plan.deletes, vec![3], "a row left with nothing is removed");
        assert_eq!(plan.updates.iter().map(|r| (r.number, r.units, r.count)).collect::<Vec<_>>(), vec![(1, 2.0, 1), (2, 1.0, 1)]);
        assert!(plan.updates[1].is_alcohol_free, "a rebuild does not clear a dry mark");
        assert_eq!(plan.inserts.iter().map(|r| (r.number, r.units)).collect::<Vec<_>>(), vec![(7, 3.0)]);
    }

    #[test]
    fn a_strength_matching_the_drinks_needs_no_override() {
        assert_eq!(logbook_abv_override(5.0, Some(5.0)), None);
        assert_eq!(logbook_abv_override(5.0, Some(5.2)), Some(5.2));
        assert_eq!(logbook_abv_override(5.0, None), None);
    }

    #[test]
    fn editing_a_drinks_strength_or_kind_retotals_its_days() {
        assert!(logbook_drink_edit_retotals(4.0, CategoryKind::Beer, 4.5, CategoryKind::Beer));
        assert!(logbook_drink_edit_retotals(4.0, CategoryKind::Beer, 4.0, CategoryKind::Stout));
        assert!(!logbook_drink_edit_retotals(4.0, CategoryKind::Beer, 4.0, CategoryKind::Beer));
    }

    #[test]
    fn a_price_reset_changes_only_what_drifted_and_only_what_the_catalogue_prices() {
        let listed = catalog_price("Beer".into(), CategoryKind::Beer, VesselKind::Pint, 568.0, "GBP".into()).expect("the generic pint is priced");
        let drink = |id: &str, name: &str, price: f64| DrinkPriceIn { id: id.into(), name: name.into(), category: CategoryKind::Beer, vessel: VesselKind::Pint, volume_ml: 568.0, price };
        let favourite = |id: &str, drink_id: &str, price: f64| FavouritePriceIn { id: id.into(), drink_id: drink_id.into(), vessel: VesselKind::Pint, volume_ml: 568.0, price };
        let changes = logbook_price_resets(
            vec![drink("drifted", "Beer", 0.0), drink("current", "Beer", listed), drink("unknown", "Not In The Catalogue", 1.0)],
            vec![favourite("tile-drifted", "drifted", 0.0), favourite("tile-current", "current", listed), favourite("orphan", "missing", 0.0)],
            "GBP".into(),
        );
        assert_eq!(changes.drinks, vec![PriceChange { id: "drifted".into(), price: listed }]);
        assert_eq!(changes.favourites, vec![PriceChange { id: "tile-drifted".into(), price: listed }]);
    }
}
