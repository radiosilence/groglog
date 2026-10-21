//! The logic GrogLog's two apps share. Each app keeps its own storage and screens and hands this crate plain values,
//! so what a day is, what a unit is and what a goal asks for cannot differ between them.

mod backup;
mod catalog;
mod catalog_data;
mod categories;
mod days;
mod goal;
mod ledger;
mod logbook;
mod nights;
mod picker;
mod rates;
mod swift_json;
mod units;

uniffi::setup_scaffolding!();
