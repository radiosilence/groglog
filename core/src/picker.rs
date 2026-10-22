//! The Log grid's order. Tiles come in four tiers, each serve shown once, in the first tier it belongs to: what was
//! logged on the day, the favourites in their pinned order, the serves usually drunk at this moment, then the generic
//! drinks. Only the third tier is scored, so pinned tiles never move.
//!
//! A serve's score for a moment is the number of nights it was drunk at a similar moment, each weighted by how similar
//! and how recent, so six rounds of a guest ale on one night count once: the hour into the drinking day, the kind of
//! day, and weakly the date in the month, so a payday habit can show. Habits that change take over within weeks, since
//! each pour's weight halves every `HALF_LIFE_DAYS`. When few serves are usual for the moment, the rest of the third
//! tier is the serves drunk on the most recent nights at any time, so anyone who has been logging sees what they drink.

use std::collections::{HashMap, HashSet};

use crate::days::{day_civil, day_weekday};

/// Days for a pour's weight to halve.
const HALF_LIFE_DAYS: f64 = 45.0;
/// How far, in hours, a pour's time of day reaches.
const HOUR_SPREAD: f64 = 1.5;
/// Weight of a pour on the same weekday, the same kind of day (a weekend night or not), or neither.
const SAME_WEEKDAY: f64 = 1.0;
const SAME_KIND: f64 = 0.5;
const OTHER_DAY: f64 = 0.1;
/// How far, in days, a pour's date in the month reaches, and the most it adds to a pour on the same date.
const DATE_SPREAD: f64 = 3.0;
const DATE_WEIGHT: f64 = 0.2;
/// How much a pour counts whatever the moment, so search still prefers what is drunk often at any time.
const PRIOR: f64 = 0.02;
/// A serve is usual for a moment with at least this much weighted evidence, about three similar recent nights, and at
/// least `SHARE` of the best serve's, so a weak runner-up does not follow a strong habit onto the grid.
const EVIDENCE: f64 = 2.0;
const SHARE: f64 = 0.25;
/// A serve drunk on about two recent nights, at any time, is drunk often enough to fill the third tier.
const OFTEN: f64 = 1.5;
/// The most usual serves shown.
const CAP: usize = 6;

/// A logged drink: its serve key, the day it counted towards and how many hours into that day it was.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PickerPour {
    pub key: String,
    pub day: i64,
    pub hours: f64,
}

#[derive(uniffi::Object)]
pub struct CorePicker {
    scores: HashMap<String, f64>,
    usual: Vec<String>,
}

#[uniffi::export]
impl CorePicker {
    /// Scores every serve in `history` for the moment `hours` into `day`.
    #[uniffi::constructor]
    pub fn new(history: Vec<PickerPour>, day: i64, hours: f64) -> Self {
        // Each night counts at its closest pour to the moment.
        let mut nights: HashMap<(&str, i64), (f64, f64)> = HashMap::new();
        for pour in &history {
            // A pour logged ahead of the moment counts as current rather than growing heavier.
            let age = ((day - pour.day) as f64 + (hours - pour.hours) / 24.0).max(0.0);
            let decay = 0.5_f64.powf(age / HALF_LIFE_DAYS);
            let similar = decay * hour_weight(pour.hours, hours) * day_weight(pour.day, day) * date_weight(pour.day, day);
            let night = nights.entry((pour.key.as_str(), pour.day)).or_default();
            *night = (night.0.max(similar), night.1.max(decay));
        }
        let mut context: HashMap<String, f64> = HashMap::new();
        let mut often: HashMap<String, f64> = HashMap::new();
        let mut scores: HashMap<String, f64> = HashMap::new();
        for ((key, _), (similar, decay)) in nights {
            *context.entry(key.to_string()).or_default() += similar;
            *often.entry(key.to_string()).or_default() += decay;
            *scores.entry(key.to_string()).or_default() += similar + PRIOR * decay;
        }
        let ranked = |weights: &HashMap<String, f64>| {
            let mut ranked: Vec<(String, f64)> = weights.iter().map(|(key, weight)| (key.clone(), *weight)).collect();
            ranked.sort_by(|a, b| b.1.total_cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
            ranked
        };
        let in_context = ranked(&context);
        let best = in_context.first().map_or(0.0, |(_, score)| *score);
        let mut usual: Vec<String> = in_context
            .into_iter()
            .filter(|(_, score)| *score >= EVIDENCE && *score >= best * SHARE)
            .map(|(key, _)| key)
            .collect();
        for (key, weight) in ranked(&often) {
            if weight >= OFTEN && !usual.contains(&key) {
                usual.push(key);
            }
        }
        CorePicker { scores, usual }
    }

    /// The serves usual for the moment, most usual first, then those drunk often at any time, before any are left out
    /// for appearing in an earlier tier.
    pub fn usual(&self) -> Vec<String> {
        self.usual.clone()
    }

    /// The grid's order without a search: `added` (the day's drinks, most recent first), `favourites` in pinned order,
    /// up to `CAP` usual serves, then `generics`. `logged` holds every serve logged on the day, so one logged after the
    /// order was taken still shows, at the end, rather than moving the tiles above it.
    pub fn tiles(&self, added: Vec<String>, favourites: Vec<String>, generics: Vec<String>, logged: Vec<String>) -> Vec<String> {
        let mut seen = HashSet::new();
        let mut tiles = Vec::new();
        let mut push = |key: &String| {
            if seen.insert(key.clone()) {
                tiles.push(key.clone());
                true
            } else {
                false
            }
        };
        added.iter().chain(&favourites).for_each(|key| {
            push(key);
        });
        let mut usual = 0;
        for key in &self.usual {
            if usual == CAP {
                break;
            }
            if push(key) {
                usual += 1;
            }
        }
        generics.iter().chain(&logged).for_each(|key| {
            push(key);
        });
        tiles
    }

    /// Search results, best scored first, then in favourite order, then in the order given.
    pub fn rank(&self, keys: Vec<String>, favourites: Vec<String>) -> Vec<String> {
        let pinned: HashMap<&String, usize> = favourites.iter().enumerate().rev().map(|(index, key)| (key, index)).collect();
        let mut ranked: Vec<(usize, &String)> = keys.iter().enumerate().collect();
        ranked.sort_by(|(i, a), (j, b)| {
            let score = |key: &String| self.scores.get(key).copied().unwrap_or(0.0);
            score(b)
                .total_cmp(&score(a))
                .then_with(|| pinned.get(a).unwrap_or(&usize::MAX).cmp(pinned.get(b).unwrap_or(&usize::MAX)))
                .then_with(|| i.cmp(j))
        });
        ranked.into_iter().map(|(_, key)| key.clone()).collect()
    }
}

fn hour_weight(a: f64, b: f64) -> f64 {
    let d = (a - b) / HOUR_SPREAD;
    (-0.5 * d * d).exp()
}

/// Friday and Saturday nights come before a day off for most people, so they are the weekend.
fn is_weekend_night(day: i64) -> bool {
    day_weekday(day) >= 6
}

fn day_weight(a: i64, b: i64) -> f64 {
    if day_weekday(a) == day_weekday(b) {
        SAME_WEEKDAY
    } else if is_weekend_night(a) == is_weekend_night(b) {
        SAME_KIND
    } else {
        OTHER_DAY
    }
}

/// A bonus for a nearby date in the month, on a 31-day circle so the 30th is near the 1st.
fn date_weight(a: i64, b: i64) -> f64 {
    let gap = (day_civil(a).day - day_civil(b).day).abs() as f64;
    let d = gap.min(31.0 - gap) / DATE_SPREAD;
    1.0 + DATE_WEIGHT * (-0.5 * d * d).exp()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::days::day_number;

    fn pour(key: &str, day: i64, hours: f64) -> PickerPour {
        PickerPour { key: key.into(), day, hours }
    }

    fn keys(list: &[&str]) -> Vec<String> {
        list.iter().map(|key| key.to_string()).collect()
    }

    /// Eight weeks of K cider at 7pm Monday to Thursday and champagne at 8pm on Friday and Saturday, ending on
    /// Sunday 2026-10-18. Hours count from a 5am day start.
    fn habits() -> Vec<PickerPour> {
        let last = day_number(2026, 10, 18);
        let mut history = Vec::new();
        for day in last - 55..=last {
            match day_weekday(day) {
                2..=5 => history.push(pour("cider", day, 14.0)),
                6 | 7 => history.extend([pour("champagne", day, 15.0), pour("champagne", day, 16.0)]),
                _ => {}
            }
        }
        history
    }

    #[test]
    fn weeknight_evenings_bring_up_the_cider_and_weekend_ones_the_champagne() {
        let wednesday = day_number(2026, 10, 21);
        assert_eq!(day_weekday(wednesday), 4);
        assert_eq!(CorePicker::new(habits(), wednesday, 14.5).usual(), keys(&["cider", "champagne"]));
        let saturday = day_number(2026, 10, 24);
        assert_eq!(CorePicker::new(habits(), saturday, 15.5).usual(), keys(&["champagne", "cider"]));
    }

    #[test]
    fn a_one_off_is_not_usual() {
        let tuesday = day_number(2026, 10, 20);
        assert!(CorePicker::new(vec![pour("negroni", tuesday - 7, 14.0)], tuesday, 14.0).usual().is_empty());
        let three = (1..=3).map(|week| pour("negroni", tuesday - 7 * week, 14.0)).collect();
        assert_eq!(CorePicker::new(three, tuesday, 14.0).usual(), keys(&["negroni"]));
    }

    #[test]
    fn what_is_drunk_often_shows_at_any_time() {
        // Two recent evenings of Stella, and the grid opened mid-afternoon on a different kind of day.
        let thursday = day_number(2026, 10, 22);
        let history = vec![pour("stella", thursday - 5, 16.0), pour("stella", thursday - 6, 17.0), pour("rioja", thursday - 200, 16.0)];
        assert_eq!(CorePicker::new(history, thursday, 11.5).usual(), keys(&["stella"]));
    }

    #[test]
    fn the_usual_for_the_moment_leads_what_is_drunk_often() {
        let wednesday = day_number(2026, 10, 21);
        let mut history = habits();
        history.extend((1..=10).map(|ago| pour("ipa", wednesday - ago, 2.0)));
        assert_eq!(CorePicker::new(history, wednesday, 14.5).usual()[0], "cider");
    }

    #[test]
    fn one_long_session_is_one_night() {
        let saturday = day_number(2026, 10, 24);
        let session = (0..6).map(|round| pour("guest ale", saturday - 7, 14.0 + round as f64 * 0.5)).collect();
        assert!(CorePicker::new(session, saturday, 15.0).usual().is_empty());
    }

    #[test]
    fn the_time_of_day_separates_habits_on_the_same_day() {
        let sunday = day_number(2026, 10, 18);
        let history: Vec<PickerPour> =
            (1..=6).flat_map(|week| [pour("bloody mary", sunday - 7 * week, 7.0), pour("red wine", sunday - 7 * week, 14.0)]).collect();
        assert_eq!(CorePicker::new(history.clone(), sunday, 7.5).usual()[0], "bloody mary");
        assert_eq!(CorePicker::new(history, sunday, 14.5).usual()[0], "red wine");
    }

    #[test]
    fn an_old_habit_gives_way_to_a_new_one() {
        let thursday = day_number(2026, 10, 22);
        let old = (20..=40).map(|week| pour("lager", thursday - 7 * week, 14.0));
        let new = (1..=4).map(|week| pour("stout", thursday - 7 * week, 14.0));
        assert_eq!(CorePicker::new(old.chain(new).collect(), thursday, 14.0).usual(), keys(&["stout"]));
    }

    #[test]
    fn a_weak_runner_up_does_not_follow_a_strong_habit() {
        let friday = day_number(2026, 10, 23);
        // Every night for four months, against three recent Fridays, which alone would be usual.
        let strong = (1..=120).map(|ago| pour("ipa", friday - ago, 14.0));
        let weak: Vec<PickerPour> = (1..=3).map(|week| pour("cider", friday - 7 * week, 14.0)).collect();
        assert_eq!(CorePicker::new(weak.clone(), friday, 14.0).usual(), keys(&["cider"]));
        // The cider still shows, as drunk often, but after the habit rather than as an equal.
        assert_eq!(CorePicker::new(strong.chain(weak).collect(), friday, 14.0).usual(), keys(&["ipa", "cider"]));
    }

    #[test]
    fn the_date_in_the_month_breaks_a_tie() {
        let day = day_number(2026, 10, 26);
        // Same weekday, same hour and the same age either side of the moment's date, which only the date tells apart.
        let payday = (1..=3).map(|n| pour("champagne", day - 28 * n, 14.0));
        let other = (1..=3).map(|n| pour("prosecco", day - 28 * n - 14, 14.0));
        let history: Vec<PickerPour> = payday.chain(other).collect();
        let picker = CorePicker::new(history, day, 14.0);
        assert_eq!(picker.rank(keys(&["prosecco", "champagne"]), vec![]), keys(&["champagne", "prosecco"]));
    }

    #[test]
    fn tiers_come_in_order_without_repeats_and_usuals_are_capped() {
        let day = day_number(2026, 10, 21);
        let history: Vec<PickerPour> =
            (1..=8).flat_map(|n| (1..=4).map(move |week| pour(&format!("u{n}"), day - 7 * week, 14.0))).collect();
        let picker = CorePicker::new(history, day, 14.0);
        assert_eq!(picker.usual().len(), 8);
        let tiles = picker.tiles(keys(&["today", "u1"]), keys(&["fav", "u2"]), keys(&["beer", "fav"]), keys(&["u1", "today", "late"]));
        assert_eq!(tiles[..4], keys(&["today", "u1", "fav", "u2"]));
        // Six usuals beyond those already shown, then the generics and anything logged since.
        assert_eq!(tiles[4..10].iter().filter(|key| key.starts_with('u')).count(), 6);
        assert_eq!(tiles[10..], keys(&["beer", "late"]));
    }

    #[test]
    fn search_ranks_by_score_then_favourite_order() {
        let day = day_number(2026, 10, 21);
        let picker = CorePicker::new(vec![pour("b", day - 7, 14.0), pour("c", day - 300, 2.0)], day, 14.0);
        assert_eq!(picker.rank(keys(&["a", "c", "d", "b"]), keys(&["d", "a"])), keys(&["b", "c", "d", "a"]));
    }

    #[test]
    fn nothing_logged_leaves_the_grid_as_pinned() {
        let picker = CorePicker::new(vec![], 0, 0.0);
        assert!(picker.usual().is_empty());
        assert_eq!(picker.tiles(vec![], keys(&["fav"]), keys(&["beer"]), vec![]), keys(&["fav", "beer"]));
    }
}
