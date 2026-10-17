//! Drinking days. A day is a count of days since 1970-01-01, so day arithmetic is integer arithmetic and a night
//! logged in one timezone stays on its date in another. Anything that needs a timezone stays with the platform, which
//! passes in the wall-clock date and hour it sees.

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct Civil {
    pub year: i64,
    pub month: i64,
    pub day: i64,
}

/// Days from civil date (Howard Hinnant's algorithm), for the proleptic Gregorian calendar.
#[uniffi::export]
pub fn day_number(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

#[uniffi::export]
pub fn day_civil(number: i64) -> Civil {
    let z = number + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    Civil { year: yoe + era * 400 + i64::from(month <= 2), month, day }
}

/// 1 = Sunday … 7 = Saturday.
#[uniffi::export]
pub fn day_weekday(number: i64) -> i64 {
    (number + 4).rem_euclid(7) + 1
}

#[uniffi::export]
pub fn day_month_start(number: i64) -> i64 {
    let c = day_civil(number);
    day_number(c.year, c.month, 1)
}

#[uniffi::export]
pub fn day_days_in_month(number: i64) -> i64 {
    let c = day_civil(number);
    let next = if c.month == 12 { day_number(c.year + 1, 1, 1) } else { day_number(c.year, c.month + 1, 1) };
    next - day_month_start(number)
}

/// `yyyy-MM-dd`.
#[uniffi::export]
pub fn day_format(number: i64) -> String {
    let c = day_civil(number);
    format!("{:04}-{:02}-{:02}", c.year, c.month, c.day)
}

/// A valid `yyyy-MM-dd` date. Imported files are parsed with this, so impossible or day-first dates are refused rather
/// than rolled over into another day.
#[uniffi::export]
pub fn day_parse(text: String) -> Option<i64> {
    let parts: Vec<&str> = text.split('-').collect();
    let [year, month, day] = parts[..] else { return None };
    let number = |part: &str| if part.bytes().all(|b| b.is_ascii_digit()) { part.parse::<i64>().ok() } else { None };
    let (year, month, day) = (number(year)?, number(month)?, number(day)?);
    if !(1900..=2200).contains(&year) || !(1..=12).contains(&month) || !(1..=31).contains(&day) {
        return None;
    }
    let number = day_number(year, month, day);
    (day_civil(number) == Civil { year, month, day }).then_some(number)
}

/// The drinking day a wall-clock moment belongs to. A day runs from `rollover_hour` to `rollover_hour` the next
/// morning, so the 1am pint counts towards the night it belongs to.
#[uniffi::export]
pub fn day_drinking(local_day: i64, local_hour: i64, rollover_hour: i64) -> i64 {
    local_day - i64::from(local_hour < rollover_hour)
}

/// Whether a clock time falls after midnight within the drinking day that began the evening before.
#[uniffi::export]
pub fn day_is_after_midnight(hour: i64, rollover_hour: i64) -> bool {
    hour < rollover_hour
}

/// The first day of the week containing `day`, where `first_weekday` is 1 for Sunday and 2 for Monday.
#[uniffi::export]
pub fn day_week_start(day: i64, first_weekday: i64) -> i64 {
    day - (day_weekday(day) - first_weekday + 7) % 7
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn day_numbers_count_from_the_epoch_and_round_trip() {
        assert_eq!(day_number(1970, 1, 1), 0);
        for number in (-800..60_000).step_by(37) {
            let c = day_civil(number);
            assert_eq!(day_number(c.year, c.month, c.day), number);
        }
    }

    #[test]
    fn dates_parse_and_format() {
        assert_eq!(day_format(day_parse("2026-09-19".into()).unwrap()), "2026-09-19");
        assert_eq!(day_format(day_parse("2026-9-3".into()).unwrap()), "2026-09-03");
        assert!(day_parse("2024-02-29".into()).is_some());
        for bad in ["2025-02-29", "2026-13-01", "19-09-2026", "2026-09", "nonsense", "", "1899-12-31", "-2026-09-19", "2026-09-19-", "+2026-09-19", "2026--09-19", "2026-+9-19", "2026-09-19-01"] {
            assert_eq!(day_parse(bad.into()), None, "{bad}");
        }
    }

    #[test]
    fn calendar_facts() {
        let saturday = day_number(2026, 9, 19);
        assert_eq!(day_weekday(saturday), 7);
        assert_eq!(day_days_in_month(day_number(2024, 2, 10)), 29);
        assert_eq!(day_days_in_month(day_number(2026, 2, 10)), 28);
        assert_eq!(day_days_in_month(day_number(2026, 12, 10)), 31);
        assert_eq!(day_month_start(saturday), day_number(2026, 9, 1));
    }

    #[test]
    fn the_small_hours_belong_to_the_night_before() {
        let day = day_number(2026, 9, 20);
        assert_eq!(day_drinking(day, 1, 5), day - 1);
        assert_eq!(day_drinking(day, 5, 5), day);
        assert!(day_is_after_midnight(4, 5) && !day_is_after_midnight(5, 5));
    }

    #[test]
    fn weeks_start_on_the_first_weekday() {
        let saturday = day_number(2026, 9, 19);
        assert_eq!(day_week_start(saturday, 2), day_number(2026, 9, 14));
        assert_eq!(day_week_start(saturday, 1), day_number(2026, 9, 13));
        assert_eq!(day_week_start(day_number(2026, 9, 14), 2), day_number(2026, 9, 14));
    }
}
