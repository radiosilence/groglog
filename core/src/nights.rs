//! Body readings after a drinking day: overnight HRV, resting and sleeping heart rate, and sleep by stage, filed under
//! the night they followed. The apps read Health and resolve what needs the calendar (which night a moment belongs to,
//! whether it was overnight) and pass plain values; the filing and the averages are here.

use std::collections::{BTreeMap, HashMap};

/// With a 5am day end a night runs 8pm to 8pm, so the 11pm reading, the 3am one and the resting rate Health stamps on
/// the next morning all belong to the preceding evening: a moment's night is the drinking day of the moment this many
/// hours earlier.
const NIGHT_SHIFT_HOURS: f64 = 15.0;
/// A reading counts as overnight in the first 16 hours of that shifted day: 8pm to noon on a 5am day end.
const OVERNIGHT_HOURS: f64 = 16.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum StageKind {
    Awake,
    Core,
    Deep,
    Rem,
    /// Asleep with no stage given, as older watches record it.
    Unstaged,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ReadingKind {
    Hrv,
    RestingHr,
    SleepingHr,
}

/// A reading with the night the app worked out for it. HRV is passed only if it was taken overnight.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct ReadingIn {
    pub night: i64,
    pub value: f64,
}

/// A heart-rate sample: seconds since the epoch, and beats per minute.
#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct SampleIn {
    pub at: f64,
    pub value: f64,
}

/// A span of sleep, with the night its start belongs to. Times are seconds since the epoch.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SleepIn {
    pub night: i64,
    pub start: f64,
    pub end: f64,
    pub stage: StageKind,
    /// The recording device. Two devices recording the same night would double it, so only one is used.
    pub source: String,
}

/// A night's sleep by stage, in seconds.
#[derive(Debug, Clone, Copy, PartialEq, Default, uniffi::Record)]
pub struct SleepRow {
    pub deep: f64,
    pub core: f64,
    pub rem: f64,
    pub unstaged: f64,
    pub awake: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct NightRow {
    pub day: i64,
    pub hrv: Option<f64>,
    pub resting_hr: Option<f64>,
    /// The mean heart rate while asleep. Closer to the night than resting rate, which a watch derives over a whole day.
    pub sleeping_hr: Option<f64>,
    pub sleep: Option<SleepRow>,
}

#[derive(Debug, Clone, Copy, PartialEq, uniffi::Record)]
pub struct SpanOut {
    pub start: f64,
    pub end: f64,
}

/// How many hours earlier a moment is shifted before its drinking day is taken as its night.
#[uniffi::export]
pub fn nights_shift_hours() -> f64 {
    NIGHT_SHIFT_HOURS
}

/// Whether a reading, given as hours into its shifted day, was taken overnight. A daytime spot reading reflects the
/// day's activity, so HRV is only taken overnight.
#[uniffi::export]
pub fn nights_is_overnight(hours_into_shifted_day: f64) -> bool {
    hours_into_shifted_day < OVERNIGHT_HOURS
}

/// Seconds asleep: every stage but awake.
#[uniffi::export]
pub fn sleep_asleep(sleep: SleepRow) -> f64 {
    sleep.deep + sleep.core + sleep.rem + sleep.unstaged
}

/// REM's share of the night, only for fully staged nights, since unstaged sleep would read as no REM.
#[uniffi::export]
pub fn sleep_rem_share(sleep: SleepRow) -> Option<f64> {
    let asleep = sleep_asleep(sleep);
    (sleep.unstaged == 0.0 && asleep > 0.0).then(|| sleep.rem / asleep)
}

fn mean(values: &[f64]) -> Option<f64> {
    (!values.is_empty()).then(|| values.iter().sum::<f64>() / values.len() as f64)
}

fn means(readings: &[ReadingIn]) -> BTreeMap<i64, f64> {
    let mut grouped: BTreeMap<i64, Vec<f64>> = BTreeMap::new();
    for reading in readings {
        grouped.entry(reading.night).or_default().push(reading.value);
    }
    grouped.into_iter().filter_map(|(night, values)| mean(&values).map(|m| (night, m))).collect()
}

/// Each night's spans from the one device that recorded the most sleep that night.
fn sleep_by_night(spans: &[SleepIn]) -> BTreeMap<i64, Vec<&SleepIn>> {
    let mut nights: BTreeMap<i64, BTreeMap<&str, Vec<&SleepIn>>> = BTreeMap::new();
    for span in spans {
        nights.entry(span.night).or_default().entry(span.source.as_str()).or_default().push(span);
    }
    nights
        .into_iter()
        .map(|(night, by_source)| {
            let asleep = |spans: &Vec<&SleepIn>| spans.iter().filter(|s| s.stage != StageKind::Awake).map(|s| s.end - s.start).sum::<f64>();
            let mut best: Option<Vec<&SleepIn>> = None;
            for (_, spans) in by_source {
                if best.as_ref().is_none_or(|current| asleep(&spans) > asleep(current)) {
                    best = Some(spans);
                }
            }
            (night, best.unwrap_or_default())
        })
        .collect()
}

/// Files readings under the night they followed. A night with several readings uses their mean. Sleep is filed by when
/// it began, so a bedtime after midnight counts for the evening before. Sleeping rate uses only beats inside an asleep
/// stage.
#[uniffi::export]
pub fn nights_build(hrv: Vec<ReadingIn>, resting_hr: Vec<ReadingIn>, sleep: Vec<SleepIn>, heart_rate: Vec<SampleIn>) -> Vec<NightRow> {
    let mut rows: BTreeMap<i64, NightRow> = BTreeMap::new();
    for (day, value) in means(&hrv) {
        night_row(&mut rows, day).hrv = Some(value);
    }
    for (day, value) in means(&resting_hr) {
        night_row(&mut rows, day).resting_hr = Some(value);
    }
    let chosen = sleep_by_night(&sleep);
    // (start, end, night) of every asleep span of the chosen devices.
    let mut asleep: Vec<(f64, f64, i64)> = Vec::new();
    for (day, spans) in &chosen {
        let mut total = SleepRow::default();
        for span in spans {
            let seconds = span.end - span.start;
            match span.stage {
                StageKind::Deep => total.deep += seconds,
                StageKind::Core => total.core += seconds,
                StageKind::Rem => total.rem += seconds,
                StageKind::Unstaged => total.unstaged += seconds,
                StageKind::Awake => total.awake += seconds,
            }
        }
        night_row(&mut rows, *day).sleep = Some(total);
        asleep.extend(spans.iter().filter(|s| s.stage != StageKind::Awake).map(|s| (s.start, s.end, s.night)));
    }
    asleep.sort_by(|a, b| a.0.total_cmp(&b.0));
    let mut samples = heart_rate;
    samples.sort_by(|a, b| a.at.total_cmp(&b.at));
    let mut sleeping: BTreeMap<i64, Vec<f64>> = BTreeMap::new();
    let mut i = 0;
    for sample in samples {
        while i < asleep.len() && asleep[i].1 <= sample.at {
            i += 1;
        }
        if i >= asleep.len() || !(asleep[i].0 <= sample.at && sample.at <= asleep[i].1) {
            continue;
        }
        sleeping.entry(asleep[i].2).or_default().push(sample.value);
    }
    for (day, values) in sleeping {
        night_row(&mut rows, day).sleeping_hr = mean(&values);
    }
    rows.into_values().collect()
}

fn night_row(rows: &mut BTreeMap<i64, NightRow>, day: i64) -> &mut NightRow {
    rows.entry(day).or_insert(NightRow { day, hrv: None, resting_hr: None, sleeping_hr: None, sleep: None })
}

/// Each night's first sleep to its last, one span per night, for fetching the heart rate inside them.
#[uniffi::export]
pub fn nights_night_spans(sleep: Vec<SleepIn>) -> Vec<SpanOut> {
    let mut spans: Vec<SpanOut> = sleep_by_night(&sleep)
        .values()
        .filter(|night| !night.is_empty())
        .map(|night| {
            let asleep: Vec<&&SleepIn> = night.iter().filter(|s| s.stage != StageKind::Awake).collect();
            SpanOut {
                start: asleep.iter().map(|s| s.start).min_by(f64::total_cmp).unwrap_or(night[0].start),
                end: asleep.iter().map(|s| s.end).max_by(f64::total_cmp).unwrap_or(night[0].end),
            }
        })
        .collect();
    spans.sort_by(|a, b| a.start.total_cmp(&b.start));
    spans
}

/// The nights with readings, queried by the reports.
#[derive(uniffi::Object)]
pub struct CoreNights {
    by_day: HashMap<i64, NightRow>,
}

fn reading(row: &NightRow, kind: ReadingKind) -> Option<f64> {
    match kind {
        ReadingKind::Hrv => row.hrv,
        ReadingKind::RestingHr => row.resting_hr,
        ReadingKind::SleepingHr => row.sleeping_hr,
    }
}

#[uniffi::export]
impl CoreNights {
    #[uniffi::constructor]
    pub fn new(rows: Vec<NightRow>) -> Self {
        CoreNights { by_day: rows.into_iter().map(|row| (row.day, row)).collect() }
    }

    pub fn first(&self) -> Option<i64> {
        self.by_day.keys().min().copied()
    }

    /// The latest night before this one with a reading, however long ago.
    pub fn last(&self, kind: ReadingKind, before: i64) -> Option<i64> {
        self.by_day.iter().filter(|(day, row)| **day < before && reading(row, kind).is_some()).map(|(day, _)| *day).max()
    }

    /// The mean over a range of nights, or none if fewer than `minimum` have a reading.
    pub fn mean(&self, kind: ReadingKind, first: i64, last: i64, minimum: i64) -> Option<f64> {
        let values: Vec<f64> = (first..=last).filter_map(|day| self.by_day.get(&day).and_then(|row| reading(row, kind))).collect();
        if (values.len() as i64) >= minimum { mean(&values) } else { None }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const HOUR: f64 = 3600.0;
    const FRIDAY: i64 = 100;

    fn span(night: i64, start_hour: f64, end_hour: f64, stage: StageKind, source: &str) -> SleepIn {
        SleepIn { night, start: start_hour * HOUR, end: end_hour * HOUR, stage, source: source.into() }
    }

    fn night_of(rows: &[NightRow], day: i64) -> Option<NightRow> {
        rows.iter().copied().find(|row| row.day == day)
    }

    #[test]
    fn several_readings_in_a_night_use_their_mean() {
        let hrv = vec![ReadingIn { night: FRIDAY, value: 40.0 }, ReadingIn { night: FRIDAY, value: 50.0 }];
        let rows = nights_build(hrv, vec![ReadingIn { night: FRIDAY, value: 58.0 }], vec![], vec![]);
        assert_eq!(night_of(&rows, FRIDAY).unwrap().hrv, Some(45.0));
        assert_eq!(night_of(&rows, FRIDAY).unwrap().resting_hr, Some(58.0));
        assert!(night_of(&rows, FRIDAY - 1).is_none());
    }

    #[test]
    fn too_few_nights_is_no_average() {
        let rows = nights_build(vec![ReadingIn { night: FRIDAY - 3, value: 40.0 }, ReadingIn { night: FRIDAY - 2, value: 50.0 }], vec![], vec![], vec![]);
        let nights = CoreNights::new(rows);
        assert_eq!(nights.mean(ReadingKind::Hrv, FRIDAY - 6, FRIDAY, 3), None);
        assert_eq!(nights.mean(ReadingKind::Hrv, FRIDAY - 6, FRIDAY, 2), Some(45.0));
        assert_eq!(nights.first(), Some(FRIDAY - 3));
        assert_eq!(nights.last(ReadingKind::Hrv, FRIDAY), Some(FRIDAY - 2));
        assert_eq!(nights.last(ReadingKind::RestingHr, FRIDAY), None);
    }

    #[test]
    fn stages_add_up_and_awake_is_not_sleep() {
        let spans = vec![
            span(FRIDAY, 23.0, 24.0, StageKind::Core, "watch"),
            span(FRIDAY, 24.0, 25.0, StageKind::Deep, "watch"),
            span(FRIDAY, 25.0, 25.5, StageKind::Rem, "watch"),
            span(FRIDAY, 25.5, 25.75, StageKind::Awake, "watch"),
        ];
        let night = night_of(&nights_build(vec![], vec![], spans, vec![]), FRIDAY).unwrap().sleep.unwrap();
        assert_eq!((night.core, night.deep, night.rem, night.awake), (HOUR, HOUR, 0.5 * HOUR, 0.25 * HOUR));
        assert_eq!(sleep_asleep(night), 2.5 * HOUR);
        assert!((sleep_rem_share(night).unwrap() - 0.2).abs() < 0.0001);
        assert_eq!(sleep_rem_share(SleepRow { unstaged: 1.0, rem: 1.0, ..Default::default() }), None, "unstaged sleep reads as no REM");
    }

    #[test]
    fn two_devices_on_one_night_count_once() {
        let spans = vec![
            span(FRIDAY, 23.0, 30.0, StageKind::Core, "watch"),
            span(FRIDAY, 23.0, 26.0, StageKind::Core, "phone"),
        ];
        let night = night_of(&nights_build(vec![], vec![], spans, vec![]), FRIDAY).unwrap().sleep.unwrap();
        assert_eq!(night.core, 7.0 * HOUR);
    }

    #[test]
    fn sleeping_rate_uses_only_beats_inside_an_asleep_stage() {
        let spans = vec![
            span(FRIDAY, 23.0, 24.0, StageKind::Core, "watch"),
            span(FRIDAY, 24.0, 24.5, StageKind::Awake, "watch"),
            span(FRIDAY, 24.5, 26.0, StageKind::Deep, "watch"),
        ];
        let beat = |hour: f64, value: f64| SampleIn { at: hour * HOUR, value };
        let beats = vec![beat(22.0, 90.0), beat(23.5, 50.0), beat(24.25, 80.0), beat(25.0, 52.0), beat(27.0, 85.0)];
        let night = night_of(&nights_build(vec![], vec![], spans, beats), FRIDAY).unwrap();
        assert_eq!(night.sleeping_hr, Some(51.0));
    }

    #[test]
    fn one_span_per_night_to_fetch_within() {
        let spans = vec![
            span(FRIDAY, 22.0, 22.5, StageKind::Awake, "watch"),
            span(FRIDAY, 23.0, 26.0, StageKind::Core, "watch"),
            span(FRIDAY, 26.0, 26.5, StageKind::Awake, "watch"),
            span(FRIDAY + 1, 47.0, 54.0, StageKind::Core, "watch"),
        ];
        let out = nights_night_spans(spans);
        assert_eq!(out, vec![SpanOut { start: 23.0 * HOUR, end: 26.0 * HOUR }, SpanOut { start: 47.0 * HOUR, end: 54.0 * HOUR }]);
    }

    #[test]
    fn the_overnight_window_and_shift_are_the_ones_the_reports_assume() {
        assert_eq!(nights_shift_hours(), 15.0);
        assert!(nights_is_overnight(15.9) && !nights_is_overnight(16.0));
    }
}
