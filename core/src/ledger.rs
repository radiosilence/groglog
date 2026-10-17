//! The ledger: a read-only view over every drinking day, built from the apps' per-day rows (a few hundred a year) so it
//! is cheap to rebuild on each change. Curves need individual drinks, which the caller passes for just the days on
//! screen, as plain values. Anything that needs a timezone arrives already worked out: the day a moment belongs to and
//! how many hours into that day it falls.

use std::collections::HashMap;

use crate::days::day_week_start;
use crate::goal::{GoalSpec, ProjectionRow, goal_daily_budget as daily_budget, goal_projection};

/// One drinking day's totals, as the app keeps them, plus whether it was marked alcohol-free.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct DayRow {
    pub number: i64,
    pub is_alcohol_free: bool,
    pub units: f64,
    pub kcal: f64,
    pub cost: f64,
    pub count: i64,
    /// A manually entered spend for the day, used instead of the sum of prices.
    pub cost_override: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Default, uniffi::Record)]
pub struct TotalsRow {
    pub units: f64,
    pub kcal: f64,
    pub cost: f64,
    pub count: i64,
}

impl TotalsRow {
    fn plus(self, other: TotalsRow) -> TotalsRow {
        TotalsRow { units: self.units + other.units, kcal: self.kcal + other.kcal, cost: self.cost + other.cost, count: self.count + other.count }
    }
}

/// A point on a running total: `x` is hours into a day, or days into a week or month.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct PointRow {
    pub x: f64,
    pub units: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct WeekRow {
    pub start: i64,
    pub totals: TotalsRow,
    pub dry_days: i64,
    pub unlogged_days: i64,
    pub budget: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum StatusKind {
    Drank,
    AlcoholFree,
    Today,
    Unlogged,
    Future,
    Untracked,
}

/// A drink for the curves: the day it counted towards, how many hours into that day it was, its units, and a sort key
/// (its timestamp in seconds) that orders drinks across days.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct CurveInput {
    pub day: i64,
    pub hours: f64,
    pub units: f64,
    pub order: f64,
}

/// A drink within one day, as hours after the day starts.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct TimedUnits {
    pub hours: f64,
    pub units: f64,
}

#[derive(uniffi::Object)]
pub struct CoreLedger {
    days: HashMap<i64, DayRow>,
    today: i64,
    first_day: Option<i64>,
    first_weekday: i64,
}

#[uniffi::export]
impl CoreLedger {
    /// `today` is the current drinking day and `first_weekday` the calendar's (1 = Sunday).
    #[uniffi::constructor]
    pub fn new(days: Vec<DayRow>, today: i64, first_weekday: i64) -> Self {
        let mut map = HashMap::with_capacity(days.len());
        for row in days {
            map.entry(row.number).or_insert(row);
        }
        let first_day = map.keys().min().copied();
        CoreLedger { days: map, today, first_day, first_weekday }
    }

    pub fn first_day(&self) -> Option<i64> {
        self.first_day
    }

    pub fn totals(&self, day: i64) -> TotalsRow {
        self.days.get(&day).map_or_else(TotalsRow::default, |row| TotalsRow {
            units: row.units,
            kcal: row.kcal,
            cost: row.cost_override.unwrap_or(row.cost),
            count: row.count,
        })
    }

    /// The manually set spend for a day, which replaces the drinks' prices while set.
    pub fn spend_override(&self, day: i64) -> Option<f64> {
        self.days.get(&day).and_then(|row| row.cost_override)
    }

    /// The sum of the day's drink prices, ignoring any manual spend.
    pub fn derived_spend(&self, day: i64) -> f64 {
        self.days.get(&day).map_or(0.0, |row| row.cost)
    }

    pub fn status(&self, day: i64) -> StatusKind {
        if let Some(row) = self.days.get(&day) {
            if row.count > 0 {
                return StatusKind::Drank;
            }
            if row.is_alcohol_free {
                return StatusKind::AlcoholFree;
            }
        }
        if day > self.today {
            return StatusKind::Future;
        }
        if day == self.today {
            return StatusKind::Today;
        }
        match self.first_day {
            Some(first) if day >= first => StatusKind::Unlogged,
            _ => StatusKind::Untracked,
        }
    }

    /// `status` for `count` consecutive days from `first`, for a calendar month in one call.
    pub fn statuses(&self, first: i64, count: i64) -> Vec<StatusKind> {
        (first..first + count.max(0)).map(|day| self.status(day)).collect()
    }

    /// Has drinks or a dry mark. A day with only a manual spend is not logged.
    pub fn is_logged(&self, day: i64) -> bool {
        self.days.get(&day).is_some_and(|row| row.count > 0 || row.is_alcohol_free)
    }

    /// Consecutive alcohol-free days up to today. An empty today does not break the streak, since the day is not over.
    pub fn dry_streak(&self) -> i64 {
        let mut day = if self.status(self.today) == StatusKind::Today { self.today - 1 } else { self.today };
        let mut count = 0;
        while self.status(day) == StatusKind::AlcoholFree {
            count += 1;
            day -= 1;
        }
        count
    }

    pub fn longest_dry_streak(&self, first: i64, last: i64) -> i64 {
        let (mut best, mut run) = (0, 0);
        for day in first..=last {
            run = if self.status(day) == StatusKind::AlcoholFree { run + 1 } else { 0 };
            best = best.max(run);
        }
        best
    }

    /// Running units total across the days `first...last`, stepping at each drink. x is in days, so a heavy night shows
    /// as a steep climb rather than a single step.
    pub fn running_total(&self, entries: Vec<CurveInput>, first: i64, last: i64, through: Option<i64>) -> Vec<PointRow> {
        let through = through.unwrap_or(last);
        let mut kept: Vec<&CurveInput> = entries.iter().filter(|e| e.day >= first && e.day <= last && e.day <= through).collect();
        kept.sort_by(|a, b| a.order.total_cmp(&b.order));
        let mut total = 0.0;
        let mut points = vec![PointRow { x: 0.0, units: 0.0 }];
        for entry in kept {
            total += entry.units;
            let into = (entry.day - first) as f64 + (entry.hours / 24.0).clamp(0.0, 1.0);
            points.push(PointRow { x: into, units: total });
        }
        points
    }

    /// The week's budget as a running total, for comparing with `running_total`.
    pub fn week_budget_curve(&self, start: i64, goal: GoalSpec) -> Vec<PointRow> {
        let mut total = 0.0;
        let mut points = vec![PointRow { x: 0.0, units: 0.0 }];
        for index in 0..7 {
            let Some(budget) = daily_budget(goal, start + index) else {
                return if points.len() > 1 { points } else { Vec::new() };
            };
            total += budget;
            points.push(PointRow { x: (index + 1) as f64, units: total });
        }
        points
    }

    pub fn week(&self, start: i64, goal: GoalSpec) -> WeekRow {
        let days = start..=start + 6;
        let budgets: Vec<Option<f64>> = days.clone().map(|day| daily_budget(goal, day)).collect();
        WeekRow {
            start,
            totals: days.clone().fold(TotalsRow::default(), |sum, day| sum.plus(self.totals(day))),
            dry_days: days.clone().filter(|day| self.status(*day) == StatusKind::AlcoholFree).count() as i64,
            unlogged_days: days.filter(|day| self.status(*day) == StatusKind::Unlogged).count() as i64,
            budget: if budgets.contains(&None) { None } else { Some(budgets.iter().flatten().sum()) },
        }
    }

    /// `week` for `count` consecutive weeks from `first`, `weeks` apart by seven days.
    pub fn weeks(&self, first: i64, count: i64, goal: GoalSpec) -> Vec<WeekRow> {
        (0..count.max(0)).map(|index| self.week(first + 7 * index, goal)).collect()
    }

    /// Units a week at the rate drunk on the logged days in the range. Unlogged days are excluded rather than counted
    /// as dry, so missing nights do not make a week look light. None when nothing in the range was logged.
    pub fn weekly_average(&self, first: i64, last: i64) -> Option<f64> {
        let logged: Vec<i64> = (first..=last).filter(|day| self.is_logged(*day)).collect();
        if logged.is_empty() {
            return None;
        }
        Some(logged.iter().map(|day| self.totals(*day).units).sum::<f64>() / logged.len() as f64 * 7.0)
    }

    /// The same over the last `weeks` complete weeks, used as the default baseline for a reduction plan.
    pub fn recent_weekly_average(&self, weeks: i64) -> Option<f64> {
        let this_week = day_week_start(self.today, self.first_weekday);
        self.weekly_average(this_week - 7 * weeks, this_week - 1)
    }

    pub fn daily_budget(&self, goal: GoalSpec, day: i64) -> Option<f64> {
        daily_budget(goal, day)
    }

    pub fn projection(&self, goal: GoalSpec) -> ProjectionRow {
        goal_projection(goal, self.today)
    }

    /// Mean running total across the logged days in the range, smoothed over about half an hour. Unlogged days are
    /// excluded rather than counted as zero. The raw mean is a staircase of small steps; the line is meant to show where
    /// a typical day stands by a given hour, so it is smoothed. `smoothed: false` gives the unsmoothed mean, for reading
    /// off as a number.
    pub fn average_cumulative(&self, entries: Vec<CurveInput>, first: i64, last: i64, from: f64, smoothed: bool) -> Vec<PointRow> {
        let logged = (first..=last).filter(|day| self.is_logged(*day)).count();
        if logged == 0 {
            return Vec::new();
        }
        let mut timed: Vec<(f64, f64)> = entries.iter().filter(|e| e.day >= first && e.day <= last).map(|e| (e.hours, e.units)).collect();
        timed.sort_by(|a, b| a.0.total_cmp(&b.0));
        let mut total = 0.0;
        let mut index = 0;
        let steps = ((24.0 - from) / 0.25) as usize;
        let raw: Vec<PointRow> = (0..=steps)
            .map(|i| {
                let hour = from + i as f64 * 0.25;
                while index < timed.len() && timed[index].0 <= hour {
                    total += timed[index].1;
                    index += 1;
                }
                PointRow { x: hour, units: total / logged as f64 }
            })
            .collect();
        if !smoothed {
            return raw;
        }
        // The result must remain a running total: starting at zero, never falling, and ending on the mean. So the drinks
        // are spread over a few hours and re-accumulated, then scaled to preserve the total. Blurring the curve itself
        // would drag its ends inwards.
        let mut previous = 0.0;
        let poured: Vec<f64> = raw
            .iter()
            .map(|point| {
                let amount = point.units - previous;
                previous = point.units;
                amount
            })
            .collect();
        let week: f64 = poured.iter().sum();
        if week <= 0.0 {
            return raw;
        }
        // Two quarter-hours either side, applied twice, so the kernel tapers at the edges instead of cutting off as a
        // single box pass would.
        let span = 2usize;
        let blur = |xs: &[f64]| -> Vec<f64> {
            (0..xs.len())
                .map(|i| xs[i.saturating_sub(span)..=(i + span).min(xs.len() - 1)].iter().sum::<f64>() / (2 * span + 1) as f64)
                .collect()
        };
        let spread = blur(&blur(&poured));
        // The blur pushes a little past the end of the day, where it is lost; scaling restores it.
        let scale = week / spread.iter().sum::<f64>();
        let mut running = 0.0;
        raw.iter()
            .zip(spread)
            .map(|(point, amount)| {
                running += amount * scale;
                PointRow { x: point.x, units: running }
            })
            .collect()
    }
}

/// Running total of units through a day, as a step series from `from` to `through` hours after the day starts. `pours`
/// are the day's drinks in the order they should be walked.
#[uniffi::export]
pub fn ledger_cumulative(pours: Vec<TimedUnits>, from: f64, through: f64) -> Vec<PointRow> {
    let mut total: f64 = pours.iter().filter(|p| p.hours <= from).map(|p| p.units).sum();
    let mut points = vec![PointRow { x: from, units: total }];
    for pour in pours.iter().filter(|p| p.hours > from && p.hours <= through) {
        total += pour.units;
        points.push(PointRow { x: pour.hours, units: total });
    }
    points.push(PointRow { x: through, units: total });
    points
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::days::day_number;
    use crate::goal::tests::goal;

    fn row(number: i64) -> DayRow {
        DayRow { number, is_alcohol_free: false, units: 0.0, kcal: 0.0, cost: 0.0, count: 0, cost_override: None }
    }

    fn dry(number: i64) -> DayRow {
        DayRow { is_alcohol_free: true, ..row(number) }
    }

    fn drank(number: i64, units: f64) -> DayRow {
        DayRow { units, count: 1, ..row(number) }
    }

    const SATURDAY: fn() -> i64 = || day_number(2026, 9, 19);

    fn ledger(days: Vec<DayRow>) -> CoreLedger {
        CoreLedger::new(days, SATURDAY(), 2)
    }

    #[test]
    fn a_days_status_follows_its_row_and_the_calendar() {
        let l = ledger(vec![drank(SATURDAY() - 3, 2.0), dry(SATURDAY() - 2)]);
        assert_eq!(l.status(SATURDAY() - 3), StatusKind::Drank);
        assert_eq!(l.status(SATURDAY() - 2), StatusKind::AlcoholFree);
        assert_eq!(l.status(SATURDAY() - 1), StatusKind::Unlogged);
        assert_eq!(l.status(SATURDAY() - 9), StatusKind::Untracked);
        assert_eq!(l.status(SATURDAY()), StatusKind::Today);
        assert_eq!(l.status(SATURDAY() + 1), StatusKind::Future);
        assert_eq!(l.statuses(SATURDAY() - 3, 2), vec![StatusKind::Drank, StatusKind::AlcoholFree]);
    }

    #[test]
    fn a_spend_on_its_own_is_not_a_drinking_day() {
        let l = ledger(vec![DayRow { cost_override: Some(12.0), ..row(SATURDAY() - 1) }]);
        assert!(!l.is_logged(SATURDAY() - 1));
        assert_eq!(l.totals(SATURDAY() - 1).cost, 12.0);
        assert_eq!(l.spend_override(SATURDAY() - 1), Some(12.0));
        assert_eq!(l.derived_spend(SATURDAY() - 1), 0.0);
    }

    #[test]
    fn an_empty_today_does_not_break_a_dry_streak() {
        let l = ledger(vec![dry(SATURDAY() - 1), dry(SATURDAY() - 2), drank(SATURDAY() - 3, 1.0)]);
        assert_eq!(l.dry_streak(), 2);
        let marked = ledger(vec![dry(SATURDAY()), dry(SATURDAY() - 1)]);
        assert_eq!(marked.dry_streak(), 2);
        assert_eq!(l.longest_dry_streak(SATURDAY() - 3, SATURDAY()), 2);
    }

    #[test]
    fn the_weekly_average_leaves_out_days_nobody_logged() {
        let monday = day_number(2026, 9, 14);
        let l = ledger(vec![drank(monday, 3.0), dry(monday + 1), drank(monday + 2, 3.0)]);
        // Two drinking days and a dry one are logged; the rest of the range is unlogged. 6 units over 3 logged days, at
        // seven days a week.
        let average = l.weekly_average(monday, monday + 6).unwrap();
        assert!((average - 6.0 / 3.0 * 7.0).abs() < 0.0001);
        assert_eq!(l.weekly_average(monday + 3, monday + 6), None);
    }

    #[test]
    fn a_week_adds_up_its_days_and_its_budget() {
        let monday = day_number(2026, 9, 14);
        let g = crate::goal::GoalSpec { is_enabled: true, baseline_weekly: 70.0, start_day: monday - 30, taper: crate::goal::TaperKind::Linear, period_days: 7, reduction_units: 0.0, ..goal() };
        let l = ledger(vec![drank(monday, 3.0), dry(monday + 1)]);
        let week = l.week(monday, g);
        assert_eq!(week.totals.units, 3.0);
        assert_eq!((week.dry_days, week.unlogged_days), (1, 3), "Sunday is still to come");
        assert!((week.budget.unwrap() - 70.0).abs() < 0.0001);
        assert_eq!(l.week(monday, goal()).budget, None, "no goal, no budget");
        assert_eq!(l.weeks(monday - 7, 2, g).iter().map(|w| w.start).collect::<Vec<_>>(), vec![monday - 7, monday]);
    }

    #[test]
    fn the_week_budget_curve_climbs_by_the_days_budget() {
        let monday = day_number(2026, 9, 14);
        let g = crate::goal::GoalSpec { is_enabled: true, baseline_weekly: 70.0, start_day: monday, taper: crate::goal::TaperKind::Linear, period_days: 7, reduction_units: 0.0, ..goal() };
        let curve = ledger(vec![]).week_budget_curve(monday, g);
        assert_eq!(curve.len(), 8);
        assert!((curve[7].units - 70.0).abs() < 0.0001);
        assert!(ledger(vec![]).week_budget_curve(monday - 10, g).is_empty());
    }

    #[test]
    fn cumulative_steps_up_at_each_drink() {
        let pint = 568.0 * 5.0 / 1000.0;
        let points = ledger_cumulative(vec![TimedUnits { hours: 15.0, units: pint }, TimedUnits { hours: 20.0, units: pint }], 0.0, 24.0);
        assert_eq!(points.iter().map(|p| p.x).collect::<Vec<_>>(), vec![0.0, 15.0, 20.0, 24.0]);
        assert!((points[3].units - 2.0 * pint).abs() < 0.001);
    }

    #[test]
    fn the_running_total_places_each_drink_inside_its_day() {
        let monday = day_number(2026, 9, 14);
        let entries = vec![
            CurveInput { day: monday + 1, hours: 12.0, units: 2.0, order: 2.0 },
            CurveInput { day: monday, hours: 36.0, units: 1.0, order: 1.0 },
            CurveInput { day: monday + 9, hours: 1.0, units: 5.0, order: 3.0 },
        ];
        let points = ledger(vec![]).running_total(entries, monday, monday + 6, None);
        assert_eq!(points.iter().map(|p| p.units).collect::<Vec<_>>(), vec![0.0, 1.0, 3.0]);
        assert_eq!(points[1].x, 1.0, "past 24 hours it stays on the day's right edge");
        assert_eq!(points[2].x, 1.5);
    }

    /// The week line is smoothed only lightly, which must not cost it the two things that make it a running total: it
    /// only ever rises, and it ends on the week's mean.
    #[test]
    fn the_week_average_is_smoothed_but_still_a_running_total() {
        let day = day_number(2026, 9, 20);
        let week = (day - 7)..=(day - 1);
        let pint = 568.0 * 5.0 / 1000.0;
        // A pint on two of the seven days, hours apart, so an unsmoothed mean would step twice. The other five are
        // alcohol-free, so all seven count and the mean lands on two pints across seven days.
        let drinking = [day_number(2026, 9, 14), day_number(2026, 9, 18)];
        let rows: Vec<DayRow> = week.clone().map(|d| if drinking.contains(&d) { drank(d, pint) } else { dry(d) }).collect();
        let entries = vec![
            CurveInput { day: drinking[0], hours: 14.0, units: pint, order: 1.0 },
            CurveInput { day: drinking[1], hours: 17.0, units: pint, order: 2.0 },
        ];
        let l = CoreLedger::new(rows, day, 2);
        let points = l.average_cumulative(entries.clone(), *week.start(), *week.end(), 0.0, true);
        assert!(!points.is_empty());
        assert!(points.windows(2).all(|pair| pair[0].units <= pair[1].units + 0.0001));
        assert!((points.last().unwrap().units - 2.0 * pint / 7.0).abs() < 0.001);
        assert_eq!(points[0].units, 0.0);
        // Unsmoothed, it steps at each drink and reads off exactly.
        let raw = l.average_cumulative(entries, *week.start(), *week.end(), 0.0, false);
        assert!((raw.iter().find(|p| p.x == 14.0).unwrap().units - pint / 7.0).abs() < 0.0001);
        assert_eq!(l.average_cumulative(vec![], day + 3, day + 4, 0.0, true), vec![], "no logged days, no line");
    }

    #[test]
    fn the_recent_average_is_the_last_complete_weeks() {
        let monday = day_number(2026, 9, 14);
        let l = CoreLedger::new(vec![drank(monday - 7, 7.0), drank(monday - 6, 7.0)], monday + 5, 2);
        let average = l.recent_weekly_average(1).unwrap();
        assert!((average - 14.0 / 2.0 * 7.0).abs() < 0.0001);
    }
}
