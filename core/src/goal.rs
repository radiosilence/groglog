//! Goals: how the daily budget comes down. A taper runs from a baseline on a start day, so everything here is a function
//! of the goal and a day; the log is never read. Persistence stays with the apps, which map their stored goal onto
//! `GoalSpec` and keep their own serialised form.

/// The DHSC's UK clinical guidelines for alcohol treatment (chapter 8, harm reduction, November 2025) give ten per cent
/// a day as the ceiling, as clinical consensus rather than trial evidence, for a person a clinician has judged suitable.
/// Nothing here presents a plan as advice.
pub const SAFE_DAILY_CUT: f64 = 0.10;
/// Above this, over 65, or in poor health, the same guidance says to go slower: no more than 10% every four days.
pub const SLOWER_ABOVE_WEEKLY: f64 = 25.0 * 7.0;
/// NICE CG115 recommendation 1.3.4.1: over 15 units a day, consider assisted withdrawal.
pub const ASSISTED_WITHDRAWAL_WEEKLY: f64 = 15.0 * 7.0;
/// The level below which a taper can end. A proportional taper never reaches zero, so a plan aimed at zero would have a
/// tail months long. Alcohol services put the point at which a person can simply stop at around ten units a day. This
/// figure is not in the written guidance.
pub const STOP_FROM: f64 = 10.0 * 7.0;
/// NICE CG115 recommendation 1.3.4.5: over 30 units a day, consider inpatient or residential.
pub const INPATIENT_WEEKLY: f64 = 30.0 * 7.0;
/// The share cut each period. It is fixed at the safe ceiling, so pace is set only by how often the cut lands.
pub const STANDARD_CUT: f64 = 10.0;

const PERIODS: [i64; 4] = [1, 3, 4, 7];
/// What a linear taper can take off the daily budget each period. Two units is the maximum: at a day apart it empties a
/// heavy drinker's budget within a fortnight, and below 20 units a day it already exceeds the 10% ceiling.
const UNIT_CUTS: [f64; 4] = [0.5, 1.0, 1.5, 2.0];
/// The quickest pace offered above each level, used both to narrow the picker and as the rung a stepped taper runs at.
const LADDER: [(f64, i64); 3] = [(SLOWER_ABOVE_WEEKLY, 4), (ASSISTED_WITHDRAWAL_WEEKLY, 3), (f64::NEG_INFINITY, 1)];

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum TaperKind {
    /// Ten per cent at a time off a fixed baseline, at the quickest pace the guidance allows for the current budget.
    Dynamic,
    /// A share off a fixed baseline. Steep at first, shallow later, and never reaches zero.
    Proportional,
    /// The same number of units off every period. Reaches zero on a fixed date.
    Linear,
}

/// A goal as the maths sees it. `start_day` is the day the taper begins, which the app works out from the goal's start
/// time in its own calendar.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct GoalSpec {
    pub is_enabled: bool,
    pub taper: TaperKind,
    pub baseline_weekly: f64,
    pub reduction_percent: f64,
    pub reduction_units: f64,
    pub period_days: i64,
    pub start_day: i64,
    pub target_weekly: f64,
}

/// The fixed figures, for the apps to check their own copies against.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct GoalStandards {
    pub safe_daily_cut: f64,
    pub slower_above_weekly: f64,
    pub assisted_withdrawal_weekly: f64,
    pub stop_from: f64,
    pub inpatient_weekly: f64,
    pub standard_cut: f64,
    pub periods: Vec<i64>,
    pub unit_cuts: Vec<f64>,
    pub ladder_paces: Vec<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct ProjectionRow {
    pub target: Option<i64>,
    pub stoppable: Option<i64>,
}

#[uniffi::export]
pub fn goal_standards() -> GoalStandards {
    GoalStandards {
        safe_daily_cut: SAFE_DAILY_CUT,
        slower_above_weekly: SLOWER_ABOVE_WEEKLY,
        assisted_withdrawal_weekly: ASSISTED_WITHDRAWAL_WEEKLY,
        stop_from: STOP_FROM,
        inpatient_weekly: INPATIENT_WEEKLY,
        standard_cut: STANDARD_CUT,
        periods: PERIODS.to_vec(),
        unit_cuts: UNIT_CUTS.to_vec(),
        ladder_paces: LADDER.iter().map(|rung| rung.1).collect(),
    }
}

/// The periods offered for a taper from `weekly`. Over 25 units a day the guidance sets a slower pace of no more than
/// 10% every four days, so the two quicker periods are not offered.
#[uniffi::export]
pub fn goal_periods_from(weekly: f64) -> Vec<i64> {
    let floor = LADDER.iter().find(|rung| weekly > rung.0).map_or(1, |rung| rung.1);
    let offered: Vec<i64> = PERIODS.iter().copied().filter(|days| *days >= floor).collect();
    if offered.is_empty() { vec![PERIODS[PERIODS.len() - 1]] } else { offered }
}

/// The pace to fall back on when a baseline change removes the chosen one: the quickest still offered, so raising the
/// baseline slows the taper as little as possible.
#[uniffi::export]
pub fn goal_nearest_offered_period(days: i64, weekly: f64) -> i64 {
    let offered = goal_periods_from(weekly);
    if offered.contains(&days) { days } else { offered.iter().copied().min().unwrap_or(PERIODS[PERIODS.len() - 1]) }
}

#[uniffi::export]
pub fn goal_nearest_offered_units(units: f64, weekly: f64, per_days: i64) -> f64 {
    let offered = goal_unit_cuts(weekly, per_days);
    if offered.contains(&units) { units } else { offered.iter().copied().fold(UNIT_CUTS[0], f64::max) }
}

/// The pace a dynamic taper runs at once the budget reaches this level: the quickest offered there, taken from the same
/// list as the picker so the two cannot disagree.
#[uniffi::export]
pub fn goal_pace_drinking(weekly: f64) -> i64 {
    goal_periods_from(weekly).into_iter().min().unwrap_or(PERIODS[PERIODS.len() - 1])
}

/// The linear amounts offered. A share scales with intake but a fixed number of units does not: two a day off a
/// ten-a-day budget is 20%, twice the ceiling, on the first day. Only amounts that open inside the ceiling are offered;
/// where none do, the smallest is kept so the picker is never empty.
#[uniffi::export]
pub fn goal_unit_cuts(weekly: f64, per_days: i64) -> Vec<f64> {
    let ceiling = weekly / 7.0 * SAFE_DAILY_CUT * per_days.max(1) as f64;
    let offered: Vec<f64> = UNIT_CUTS.iter().copied().filter(|cut| *cut <= ceiling + 0.0001).collect();
    if offered.is_empty() { vec![UNIT_CUTS[0]] } else { offered }
}

/// The offered period closest in pace to a rate, for a goal saved with a period no longer offered. The daily rate is
/// matched rather than the number of days, which could make a long taper several times faster.
#[uniffi::export]
pub fn goal_nearest_period_to_daily_cut(cut: f64) -> i64 {
    PERIODS
        .iter()
        .copied()
        .min_by(|a, b| {
            let (da, db) = ((daily_cut(STANDARD_CUT, *a) - cut).abs(), (daily_cut(STANDARD_CUT, *b) - cut).abs());
            da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal)
        })
        .unwrap_or(1)
}

/// The daily rate a pace compounds to.
#[uniffi::export]
pub fn goal_rate_for_pace(days: i64) -> f64 {
    daily_cut(STANDARD_CUT, days)
}

fn daily_cut(reduction_percent: f64, period_days: i64) -> f64 {
    1.0 - (1.0 - reduction_percent / 100.0).powf(1.0 / period_days.max(1) as f64)
}

/// The equivalent share per day, for comparing proportional plans on the same footing.
#[uniffi::export]
pub fn goal_daily_cut(goal: GoalSpec) -> f64 {
    daily_cut(goal.reduction_percent, goal.period_days)
}

/// Units off the daily budget per day, for a linear plan.
#[uniffi::export]
pub fn goal_daily_unit_cut(goal: GoalSpec) -> f64 {
    goal.reduction_units / goal.period_days.max(1) as f64
}

/// A linear taper takes the same units off whatever the budget, so the share it takes climbs as the budget falls: it
/// passes the safe rate at this daily budget and is sharper than it from there down.
#[uniffi::export]
pub fn goal_sharpens_below(goal: GoalSpec) -> f64 {
    goal_daily_unit_cut(goal) / SAFE_DAILY_CUT
}

/// Whether to warn about it. The 10%-a-day limit concerns withdrawal from heavy drinking and has no meaning near the
/// guideline, where warning would contradict the advice on the same screen.
#[uniffi::export]
pub fn goal_sharpens_while_it_matters(goal: GoalSpec, weekly: f64) -> bool {
    goal.taper == TaperKind::Linear
        && weekly >= ASSISTED_WITHDRAWAL_WEEKLY
        && goal_sharpens_below(goal) > crate::units::units_weekly_guideline() / 7.0
}

#[uniffi::export]
pub fn goal_is_faster_than_safe(goal: GoalSpec) -> bool {
    match goal.taper {
        TaperKind::Dynamic | TaperKind::Proportional => goal_daily_cut(goal) > SAFE_DAILY_CUT + 0.0005,
        // Safe at the start and too fast at the end, so a single answer would be wrong; `goal_sharpens_below` gives the
        // crossover.
        TaperKind::Linear => false,
    }
}

/// What this takes off the budget on its first day: the steepest step of a proportional taper, and every step of a
/// linear one.
#[uniffi::export]
pub fn goal_opening_drop(goal: GoalSpec, weekly: f64) -> f64 {
    match goal.taper {
        TaperKind::Linear => goal_daily_unit_cut(goal),
        // Stepped starts on whichever rung its baseline lands it on.
        TaperKind::Dynamic => weekly / 7.0 * goal_rate_for_pace(goal_pace_drinking(weekly)),
        TaperKind::Proportional => weekly / 7.0 * goal_daily_cut(goal),
    }
}

/// The unfloored budget for `day` and the level it tapers from. All tapers run from the baseline on the start date:
/// proportional takes a share off, linear a fixed number of units (so it can reach zero), and stepped takes the share
/// its ladder gives for the level the budget has reached.
fn taper(goal: &GoalSpec, day: i64) -> Option<(f64, f64)> {
    if !goal.is_enabled {
        return None;
    }
    let elapsed = day - goal.start_day;
    if elapsed < 0 {
        return None;
    }
    let reference = goal.baseline_weekly / 7.0;
    Some(match goal.taper {
        TaperKind::Linear => ((reference - goal_daily_unit_cut(*goal) * elapsed as f64).max(0.0), reference),
        TaperKind::Proportional => (reference * (1.0 - goal_daily_cut(*goal)).powf(elapsed as f64), reference),
        TaperKind::Dynamic => {
            // Pace changes one rung at a time on the way down. Within a rung the decline is geometric, so the crossing
            // into the next rung is solved with a logarithm rather than by stepping day by day: this runs for every
            // calendar cell and chart point, and stepping a long-running goal would dominate those screens.
            let mut budget = reference;
            let mut days = elapsed;
            for (above, pace) in LADDER {
                if !(days > 0 && budget * 7.0 > above) {
                    continue;
                }
                let factor = 1.0 - goal_rate_for_pace(pace);
                let mut steps = days;
                if above > 0.0 {
                    // The first count of cuts that leaves it no longer above the rung, adjusted either way so a
                    // floating-point error in the logarithm cannot misplace the crossing by a day.
                    steps = ((above / (budget * 7.0)).ln() / factor.ln()).ceil().max(0.0) as i64;
                    while steps > 0 && budget * factor.powf((steps - 1) as f64) * 7.0 <= above {
                        steps -= 1;
                    }
                    while budget * factor.powf(steps as f64) * 7.0 > above {
                        steps += 1;
                    }
                    steps = steps.min(days);
                }
                budget *= factor.powf(steps as f64);
                days -= steps;
            }
            (budget, reference)
        }
    })
}

/// The unit budget for `day`: the taper, held at the target once it gets there. None before the goal starts or while it
/// is off.
#[uniffi::export]
pub fn goal_daily_budget(goal: GoalSpec, day: i64) -> Option<f64> {
    taper(&goal, day).map(|(budget, reference)| budget.max((goal.target_weekly / 7.0).min(reference)))
}

/// How many days the budget takes to lose a tenth on `day`: the chosen period, or for a stepped taper the pace of the
/// rung its budget has reached (the baseline's rung before it starts).
#[uniffi::export]
pub fn goal_pace_on(goal: GoalSpec, day: i64) -> i64 {
    if goal.taper != TaperKind::Dynamic {
        return goal.period_days;
    }
    goal_pace_drinking(taper(&goal, day).map_or(goal.baseline_weekly / 7.0, |(budget, _)| budget) * 7.0)
}

/// How far ahead a projection looks before deciding a level is never reached.
const HORIZON_DAYS: i64 = 100 * 365;

/// When the taper, continued from `today`, reaches the target and the level at which drinking can stop (`STOP_FROM`).
/// The days are found on the budget itself, so a stepped taper is projected at the pace of each rung it passes through.
#[uniffi::export]
pub fn goal_projection(goal: GoalSpec, today: i64) -> ProjectionRow {
    let none = ProjectionRow { target: None, stoppable: None };
    let Some((budget_now, _)) = taper(&goal, today) else { return none };
    let falls = match goal.taper {
        TaperKind::Linear => goal_daily_unit_cut(goal) > 0.0,
        TaperKind::Proportional => goal_daily_cut(goal) > 0.0,
        TaperKind::Dynamic => true,
    };
    if !falls {
        return none;
    }
    let budget = |day: i64| taper(&goal, day).map_or(budget_now, |(budget, _)| budget);
    let reaching = |level: f64| -> Option<i64> {
        // A linear taper falls at a fixed rate and can reach zero; a share taken off never does.
        if level < 0.0 || (level == 0.0 && goal.taper != TaperKind::Linear) {
            return None;
        }
        if budget_now <= level {
            return Some(today);
        }
        // The budget only falls, so the crossing is bracketed by doubling the step and then found by halving it.
        let mut step = 1;
        while budget(today + step) > level {
            step *= 2;
            if step > HORIZON_DAYS {
                return None;
            }
        }
        let (mut above, mut at) = (today + step / 2, today + step);
        while at - above > 1 {
            let middle = above + (at - above) / 2;
            if budget(middle) > level { above = middle } else { at = middle }
        }
        Some(at)
    };
    ProjectionRow { target: reaching(goal.target_weekly / 7.0), stoppable: reaching(STOP_FROM / 7.0) }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::days::day_number;

    pub fn goal() -> GoalSpec {
        GoalSpec {
            is_enabled: false,
            taper: TaperKind::Dynamic,
            baseline_weekly: 28.0,
            reduction_percent: STANDARD_CUT,
            reduction_units: 1.0,
            period_days: 4,
            start_day: 0,
            target_weekly: 0.0,
        }
    }

    fn weekly() -> GoalSpec {
        GoalSpec {
            is_enabled: true,
            taper: TaperKind::Proportional,
            baseline_weekly: 70.0,
            reduction_percent: 10.0,
            period_days: 7,
            start_day: day_number(2026, 9, 1),
            target_weekly: 14.0,
            ..goal()
        }
    }

    const START: fn() -> i64 = || day_number(2026, 9, 1);

    #[test]
    fn schedule_compounds_smoothly_per_period() {
        let g = weekly();
        assert_eq!(goal_daily_budget(g, START()), Some(10.0));
        assert!((goal_daily_budget(g, START() + 7).unwrap() - 9.0).abs() < 0.0001);
        let mid = goal_daily_budget(g, START() + 3).unwrap();
        assert!(mid < 10.0 && mid > 9.0);
        assert_eq!(goal_daily_budget(g, START() + 800), Some(2.0));
        assert_eq!(goal_daily_budget(g, START() - 1), None);
    }

    #[test]
    fn ten_percent_a_day_is_exactly_the_safe_limit() {
        let daily = GoalSpec { period_days: 1, ..weekly() };
        assert!(!goal_is_faster_than_safe(daily));
        assert!(goal_is_faster_than_safe(GoalSpec { reduction_percent: 25.0, ..daily }));
    }

    #[test]
    fn projects_target_and_stop_dates() {
        let today = day_number(2026, 9, 20);
        let g = GoalSpec { start_day: today, ..weekly() };
        let projection = goal_projection(g, today);
        assert!((105..=109).contains(&(projection.target.unwrap() - today)));
        // It starts at ten a day, which is already low enough to stop from, so the stop date is today rather than
        // months out at the tail of the curve.
        assert_eq!(projection.stoppable, Some(today));
    }

    #[test]
    fn nothing_you_can_pick_is_faster_than_is_safe() {
        for days in PERIODS {
            let g = GoalSpec { is_enabled: true, period_days: days, ..goal() };
            assert!(!goal_is_faster_than_safe(g), "{STANDARD_CUT}% every {days} days is {} a day", goal_daily_cut(g));
        }
    }

    #[test]
    fn the_period_is_the_whole_of_the_pace() {
        let paces: Vec<f64> = PERIODS.iter().map(|days| goal_daily_cut(GoalSpec { period_days: *days, ..goal() })).collect();
        assert!(paces.windows(2).all(|pair| pair[0] >= pair[1]), "a day apart is the fastest, a week apart the gentlest");
        assert!((paces[0] - 0.10).abs() < 0.0001);
        assert!(paces[paces.len() - 1] < 0.02);
    }

    #[test]
    fn the_default_is_ten_percent_every_four_days_to_nothing() {
        let g = goal();
        assert!(g.reduction_percent == 10.0 && g.period_days == 4 && g.target_weekly == 0.0);
        assert!((goal_daily_cut(g) - 0.026).abs() < 0.001);
        assert!(!goal_is_faster_than_safe(g));
        let today = day_number(2026, 9, 20);
        let projection = goal_projection(GoalSpec { is_enabled: true, taper: TaperKind::Proportional, baseline_weekly: 70.0, start_day: today, ..goal() }, today);
        assert_eq!(projection.target, None, "a share never reaches nothing");
        assert!(projection.stoppable.is_some(), "and it always reaches a level it can be stopped from");
    }

    #[test]
    fn a_retired_period_moves_to_whichever_keeps_the_pace() {
        // -50% a week was 9.4% a day, which is nearest to 10% every day.
        assert_eq!(goal_nearest_period_to_daily_cut(daily_cut(50.0, 7)), 1, "9.4% a day belongs next to 10% a day");
        // -10% every twelve weeks was 0.1% a day, which is nearest to the gentlest still offered.
        assert_eq!(goal_nearest_period_to_daily_cut(daily_cut(10.0, 84)), 7);
    }

    #[test]
    fn the_limits_are_the_ones_the_guidance_gives() {
        assert_eq!(SAFE_DAILY_CUT, 0.10);
        assert_eq!(SLOWER_ABOVE_WEEKLY / 7.0, 25.0);
        assert_eq!(ASSISTED_WITHDRAWAL_WEEKLY / 7.0, 15.0);
        assert_eq!(INPATIENT_WEEKLY / 7.0, 30.0);
        assert!(goal().period_days == 4 && goal().reduction_percent == 10.0);
    }

    #[test]
    fn nothing_offered_starts_steeper_than_the_ceiling() {
        let mut daily = 4.0;
        while daily <= 80.0 {
            let weekly = daily * 7.0;
            for days in goal_periods_from(weekly) {
                assert!(!goal_is_faster_than_safe(GoalSpec { period_days: days, ..goal() }));
                for units in goal_unit_cuts(weekly, days) {
                    let opening = units / days as f64 / daily;
                    // The smallest cut always stands, even where a tenth of the drinking is less than it.
                    if units > UNIT_CUTS[0] && weekly >= ASSISTED_WITHDRAWAL_WEEKLY {
                        assert!(opening <= SAFE_DAILY_CUT + 0.0001, "−{units} u every {days} days on {daily} u/day opens at {opening}");
                    }
                }
            }
            daily += 2.0;
        }
    }

    #[test]
    fn a_fast_taper_is_withheld_from_whoever_is_drinking_most() {
        assert_eq!(goal_periods_from(14.0 * 7.0), vec![1, 3, 4, 7]);
        assert_eq!(goal_periods_from(20.0 * 7.0), vec![3, 4, 7], "ours, on NICE's line at 15");
        assert_eq!(goal_periods_from(40.0 * 7.0), vec![4, 7]);
    }

    #[test]
    fn no_linear_amount_opens_steeper_than_ten_per_cent() {
        let mut daily = 4.0;
        while daily <= 80.0 {
            for days in goal_periods_from(daily * 7.0) {
                for units in goal_unit_cuts(daily * 7.0, days) {
                    if units > UNIT_CUTS[0] {
                        assert!(units / days as f64 / daily <= SAFE_DAILY_CUT + 0.0001, "−{units} u every {days} days on {daily} u/day");
                    }
                }
            }
            daily += 1.0;
        }
    }

    #[test]
    fn dynamic_quickens_as_the_budget_falls() {
        let g = GoalSpec { is_enabled: true, taper: TaperKind::Dynamic, baseline_weekly: 40.0 * 7.0, start_day: START(), ..goal() };
        let day = |n: i64| goal_daily_budget(g, START() + n).unwrap();
        // It opens on the rung the guidance names for over 25 a day.
        assert!(((day(0) - day(1)) / 40.0 - goal_rate_for_pace(4)).abs() < 0.0001);
        // And by the time the budget is under fifteen it's on the quickest.
        let at60 = day(60);
        assert!(((at60 - day(61)) / at60 - goal_rate_for_pace(1)).abs() < 0.0001);
        // Falling all the way, and never faster than the ceiling.
        assert!(day(60) < day(30) && day(30) < day(0));
        let steps: Vec<f64> = (0..90).map(|n| (day(n) - day(n + 1)) / day(n)).collect();
        assert!(steps.iter().all(|step| *step <= SAFE_DAILY_CUT + 0.0001));
        assert!(steps[0] < steps[steps.len() - 1], "gentle at the top, quick at the bottom");
    }

    #[test]
    fn the_ladder_is_whatever_the_picker_would_offer() {
        let mut daily = 4.0;
        while daily <= 80.0 {
            assert_eq!(Some(goal_pace_drinking(daily * 7.0)), goal_periods_from(daily * 7.0).into_iter().min(), "at {daily} u/day");
            daily += 1.0;
        }
        assert_eq!(goal_pace_drinking(40.0 * 7.0), 4, "the DHSC limit over 25 a day");
        assert_eq!(goal_pace_drinking(20.0 * 7.0), 3, "ours, on NICE's line at 15");
        assert_eq!(goal_pace_drinking(14.0 * 7.0), 1, "the ceiling, under it");
    }

    #[test]
    fn a_stepped_tapers_pace_is_the_rung_it_has_reached() {
        let g = GoalSpec { is_enabled: true, taper: TaperKind::Dynamic, baseline_weekly: 40.0 * 7.0, period_days: 7, start_day: START(), ..goal() };
        assert_eq!(goal_pace_on(g, START() - 5), 4, "before it starts, its baseline's rung");
        assert_eq!(goal_pace_on(g, START()), 4);
        assert_eq!(goal_pace_on(g, START() + 90), 1);
        assert_eq!(goal_pace_on(GoalSpec { taper: TaperKind::Proportional, ..g }, START() + 90), 7, "any other taper is the period it was given");
    }

    #[test]
    fn raising_the_start_moves_to_the_next_pace_still_offered() {
        assert_eq!(goal_nearest_offered_period(1, 14.0 * 7.0), 1);
        assert_eq!(goal_nearest_offered_period(1, 20.0 * 7.0), 3);
        assert_eq!(goal_nearest_offered_period(1, 30.0 * 7.0), 4);
        assert_eq!(goal_nearest_offered_period(3, 30.0 * 7.0), 4);
        assert_eq!(goal_nearest_offered_period(4, 80.0 * 7.0), 4);
    }

    #[test]
    fn raising_the_start_keeps_a_linear_cut_if_it_can() {
        assert_eq!(goal_nearest_offered_units(2.0, 40.0 * 7.0, 1), 2.0);
        assert_eq!(goal_nearest_offered_units(2.0, 18.0 * 7.0, 1), 1.5);
        assert_eq!(goal_nearest_offered_units(2.0, 10.0 * 7.0, 1), 1.0);
        assert_eq!(goal_nearest_offered_units(2.0, 18.0 * 7.0, 4), 2.0);
    }

    #[test]
    fn the_opening_step_is_what_the_percentage_hides() {
        let proportional = GoalSpec { taper: TaperKind::Proportional, period_days: 1, ..goal() };
        assert!((goal_opening_drop(proportional, 60.0 * 7.0) - 6.0).abs() < 0.0001, "a tenth of sixty");
        // Dynamic's is whatever rung sixty a day puts it on, which is the gentlest.
        assert!((goal_opening_drop(goal(), 60.0 * 7.0) - 60.0 * goal_rate_for_pace(4)).abs() < 0.0001);
        let linear = GoalSpec { taper: TaperKind::Linear, reduction_units: 2.0, period_days: 4, ..goal() };
        assert!((goal_opening_drop(linear, 60.0 * 7.0) - 0.5).abs() < 0.0001);
    }

    #[test]
    fn a_linear_cut_is_withheld_wherever_it_would_open_too_steep() {
        assert_eq!(goal_unit_cuts(18.0 * 7.0, 1), vec![0.5, 1.0, 1.5]);
        assert_eq!(goal_unit_cuts(40.0 * 7.0, 1), UNIT_CUTS.to_vec());
        assert_eq!(goal_unit_cuts(10.0 * 7.0, 1), vec![0.5, 1.0]);
        assert_eq!(goal_unit_cuts(15.0 * 7.0, 1), vec![0.5, 1.0, 1.5]);
        assert_eq!(goal_unit_cuts(2.0 * 7.0, 1), vec![0.5], "however little is drunk, the smallest stands");
        assert_eq!(goal_unit_cuts(18.0 * 7.0, 4), UNIT_CUTS.to_vec());
    }

    fn linear() -> GoalSpec {
        GoalSpec { is_enabled: true, taper: TaperKind::Linear, baseline_weekly: 70.0, reduction_units: 1.0, period_days: 7, start_day: START(), target_weekly: 0.0, ..goal() }
    }

    #[test]
    fn linear_comes_down_by_the_same_amount_every_day() {
        let day = |n: i64| goal_daily_budget(linear(), START() + n).unwrap();
        assert!((day(0) - 10.0).abs() < 0.0001);
        assert!((day(7) - 9.0).abs() < 0.0001);
        assert!(day(70).abs() < 0.0001);
        let steps: Vec<f64> = (0..30).map(|n| day(n + 1) - day(n)).collect();
        assert!(steps.iter().all(|step| (step - steps[0]).abs() < 0.0001));
        assert_eq!(day(140), 0.0, "and stays there");
    }

    #[test]
    fn linear_has_a_date_for_nothing_where_proportional_never_does() {
        let today = day_number(2026, 9, 20);
        let landing = GoalSpec { start_day: today, ..linear() };
        let easing = GoalSpec { taper: TaperKind::Proportional, start_day: today, ..linear() };
        assert!(goal_projection(landing, today).target.is_some());
        assert!(goal_projection(easing, today).target.is_none());
    }

    #[test]
    fn linear_says_where_it_starts_cutting_faster_than_is_safe() {
        assert!((goal_sharpens_below(linear()) - (1.0 / 7.0) / SAFE_DAILY_CUT).abs() < 0.0001);
        assert!(!goal_is_faster_than_safe(linear()));
    }

    #[test]
    fn linear_says_nothing_where_the_guideline_would_contradict_it() {
        assert!(goal_sharpens_below(linear()) < crate::units::units_weekly_guideline() / 7.0);
        assert!(!goal_sharpens_while_it_matters(linear(), 40.0 * 7.0));
        let brisk = GoalSpec { period_days: 1, ..linear() };
        assert_eq!(goal_sharpens_below(brisk), 10.0);
        assert!(goal_sharpens_while_it_matters(brisk, 40.0 * 7.0));
        assert!(!goal_sharpens_while_it_matters(brisk, 10.0 * 7.0), "nothing to warn about at ten a day");
        assert!(!goal_sharpens_while_it_matters(GoalSpec { taper: TaperKind::Proportional, ..brisk }, 40.0 * 7.0));
    }

    /// A stepped taper quickens as it falls, so its dates come from the budget it actually follows, not from the pace
    /// it opened at.
    #[test]
    fn a_stepped_taper_is_projected_to_the_day_its_budget_crosses() {
        let g = GoalSpec { is_enabled: true, taper: TaperKind::Dynamic, baseline_weekly: 40.0 * 7.0, target_weekly: 14.0, start_day: START(), ..goal() };
        let projection = goal_projection(g, START());
        for (day, level) in [(projection.target.unwrap(), 2.0), (projection.stoppable.unwrap(), STOP_FROM / 7.0)] {
            assert!(taper(&g, day - 1).unwrap().0 > level && taper(&g, day).unwrap().0 <= level, "{level} a day");
        }
        // Projected at the opening rung's pace all the way down, the stop date would be over a fortnight later.
        let opening_pace = (STOP_FROM / 7.0 / 40.0).ln() / (1.0 - goal_rate_for_pace(4)).ln();
        assert!(((projection.stoppable.unwrap() - START()) as f64) < opening_pace - 14.0);
    }

    #[test]
    fn closed_form_tapers_project_where_their_formulas_say() {
        let today = day_number(2026, 9, 20);
        let linear = GoalSpec { start_day: today, ..linear() };
        assert_eq!(goal_projection(linear, today).target, Some(today + 70), "ten a day, a seventh of a unit off each day");
        let proportional = GoalSpec { start_day: today, ..weekly() };
        let days = (2.0f64 / 10.0).ln() / (1.0 - goal_daily_cut(proportional)).ln();
        assert_eq!(goal_projection(proportional, today).target, Some(today + days.ceil() as i64));
    }
}
