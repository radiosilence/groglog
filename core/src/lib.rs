//! The logic GrogLog's two apps share. Each app keeps its own storage and screens and hands this crate plain values,
//! so what a day is, what a unit is and what a goal asks for cannot differ between them.

mod days;
mod units;

uniffi::setup_scaffolding!();
