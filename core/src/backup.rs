//! The backup document: everything, as one self-describing file. Days are listed explicitly, including unlogged ones, so
//! a reader (human or LLM) can tell a dry day from a gap. Reading is lenient: only `days[].date` and `days[].status`
//! are required, so other apps' data can be hand-converted (see docs/IMPORT.md).
//!
//! This holds the format, the assembly of an export from the app's rows, the markdown text, and the planning of a
//! restore as a list of operations. The apps keep the database: they read a snapshot of what exists, ask for a plan,
//! and apply it in one transaction. The goal is carried as an opaque JSON object, because each app keeps its own goal
//! codec, with its migrations for goals saved by older builds.

use std::collections::HashSet;
use std::fmt;
use std::sync::Arc;

use serde::de::Error as _;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;

use crate::categories::{default_abv, default_vessel, is_category, is_vessel};
use crate::days::{day_format, day_parse};
use crate::goal::{GoalSpec, STOP_FROM, goal_projection};
use crate::ledger::{CoreLedger, DayRow, StatusKind};
use crate::swift_json;

const NOTES: &str = "UK units: 1 unit = 10 ml pure alcohol. Days run from dayStartsAtHour to the same hour next morning. status is drank, alcohol_free (explicitly marked), not_logged (unknown; do not assume dry) or in_progress (today).";

#[derive(Debug, uniffi::Error)]
pub enum BackupError {
    Unreadable { reason: String },
    DayEndsAtImpossibleHour { hour: i64 },
}

impl fmt::Display for BackupError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BackupError::Unreadable { reason } => write!(f, "The file is not a GrogLog backup: {reason}"),
            BackupError::DayEndsAtImpossibleHour { hour } => {
                write!(f, "The file sets the day to end at hour {hour}, which is not an hour of the day.")
            }
        }
    }
}

impl std::error::Error for BackupError {}

// MARK: Document

/// An id as iOS writes it, upper case; either case reads.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct Id(String);

impl Id {
    fn parse(text: &str) -> Option<Id> {
        if text.len() != 36 {
            return None;
        }
        uuid::Uuid::parse_str(text).ok().map(|id| Id(id.hyphenated().encode_upper(&mut uuid::Uuid::encode_buffer()).to_string()))
    }

    fn random() -> Id {
        Id(uuid::Uuid::new_v4().hyphenated().encode_upper(&mut uuid::Uuid::encode_buffer()).to_string())
    }
}

impl Serialize for Id {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.0)
    }
}

impl<'de> Deserialize<'de> for Id {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Id, D::Error> {
        let text = String::deserialize(deserializer)?;
        Id::parse(&text).ok_or_else(|| D::Error::custom(format!("expected a UUID, got {text}")))
    }
}

/// A name from a closed list, which the file is refused for getting wrong.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Named<const VESSEL: bool>(String);

impl<const VESSEL: bool> Serialize for Named<VESSEL> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&self.0)
    }
}

impl<'de, const VESSEL: bool> Deserialize<'de> for Named<VESSEL> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let text = String::deserialize(deserializer)?;
        let known = if VESSEL { is_vessel(&text) } else { is_category(&text) };
        if known { Ok(Named(text)) } else { Err(D::Error::custom(format!("unknown {} {text}", if VESSEL { "vessel" } else { "category" }))) }
    }
}

type Category = Named<false>;
type Vessel = Named<true>;

/// Dates as iOS's `JSONEncoder` writes them with its `.iso8601` strategy: UTC, whole seconds, `Z`. Reading also takes an
/// offset or fractional seconds, which hand-written imports use.
mod iso {
    use super::*;

    pub fn serialize<S: Serializer>(value: &Option<i64>, serializer: S) -> Result<S::Ok, S::Error> {
        match value {
            Some(seconds) => serializer.serialize_str(&format(*seconds)),
            None => serializer.serialize_none(),
        }
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Option<i64>, D::Error> {
        match Option::<String>::deserialize(deserializer)? {
            None => Ok(None),
            Some(text) => parse(&text).map(Some).ok_or_else(|| D::Error::custom(format!("expected an ISO 8601 date, got {text}"))),
        }
    }

    pub fn format(seconds: i64) -> String {
        let day = seconds.div_euclid(86_400);
        let rest = seconds.rem_euclid(86_400);
        let civil = crate::days::day_civil(day);
        format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", civil.year, civil.month, civil.day, rest / 3600, rest % 3600 / 60, rest % 60)
    }

    /// Seconds since the epoch, for `yyyy-MM-ddTHH:mm:ss`, optional fractional seconds (dropped), and an offset.
    pub fn parse(text: &str) -> Option<i64> {
        let bytes = text.as_bytes();
        let digits = |range: std::ops::Range<usize>| -> Option<i64> {
            let part = bytes.get(range)?;
            if part.iter().all(u8::is_ascii_digit) { std::str::from_utf8(part).ok()?.parse().ok() } else { None }
        };
        if bytes.len() < 20 || bytes[4] != b'-' || bytes[7] != b'-' || !(bytes[10] == b'T' || bytes[10] == b't') || bytes[13] != b':' || bytes[16] != b':' {
            return None;
        }
        let (year, month, day) = (digits(0..4)?, digits(5..7)?, digits(8..10)?);
        let (hour, minute, second) = (digits(11..13)?, digits(14..16)?, digits(17..19)?);
        if !(1..=12).contains(&month) || !(1..=31).contains(&day) || hour > 23 || minute > 59 || second > 60 {
            return None;
        }
        let days = crate::days::day_number(year, month, day);
        let civil = crate::days::day_civil(days);
        if (civil.year, civil.month, civil.day) != (year, month, day) {
            return None;
        }
        let mut at = 19;
        if bytes.get(at) == Some(&b'.') {
            at += 1;
            let start = at;
            while bytes.get(at).is_some_and(u8::is_ascii_digit) {
                at += 1;
            }
            if at == start {
                return None;
            }
        }
        let offset = match bytes.get(at)? {
            b'Z' | b'z' if at + 1 == bytes.len() => 0,
            sign @ (b'+' | b'-') => {
                let rest = &text[at + 1..];
                // Sliced by byte below, so anything but ASCII digits and a colon is refused first.
                if !rest.bytes().all(|b| b.is_ascii_digit() || b == b':') {
                    return None;
                }
                let (h, m) = match rest.len() {
                    2 => (rest.parse::<i64>().ok()?, 0),
                    4 => (rest[..2].parse::<i64>().ok()?, rest[2..].parse::<i64>().ok()?),
                    5 if rest.as_bytes()[2] == b':' => (rest[..2].parse::<i64>().ok()?, rest[3..].parse::<i64>().ok()?),
                    _ => return None,
                };
                if h > 18 || m > 59 {
                    return None;
                }
                (h * 3600 + m * 60) * if *sign == b'-' { -1 } else { 1 }
            }
            _ => return None,
        };
        Some(days * 86_400 + hour * 3600 + minute * 60 + second - offset)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Doc {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    format: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none", with = "iso")]
    exported_at: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    notes: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    day_starts_at_hour: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    currency: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    goal: Option<Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    projected_stop: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    drinks: Option<Vec<DrinkRec>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    favourites: Option<Vec<FavouriteRec>>,
    days: Vec<DayRec>,
}

/// A drink's identity, with the size and price it was first added at.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DrinkRec {
    id: Id,
    name: String,
    category: Category,
    abv: f64,
    vessel: Vessel,
    volume_ml: f64,
    price: f64,
    is_generic: bool,
    is_hidden: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct FavouriteRec {
    #[serde(rename = "drinkID")]
    drink_id: Id,
    vessel: Vessel,
    volume_ml: f64,
    price: f64,
    order: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DayRec {
    date: String,
    status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    units: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    kcal: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    cost: Option<f64>,
    /// Set when the day's spend was entered manually; `cost` is then that figure rather than the sum of prices.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    spent_by_hand: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    budget: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pours: Option<Vec<PourRec>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PourRec {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    id: Option<Id>,
    #[serde(default, skip_serializing_if = "Option::is_none", with = "iso")]
    time: Option<i64>,
    name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    category: Option<Category>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    vessel: Option<Vessel>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    volume_ml: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    abv: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    units: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    kcal: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    price: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none", rename = "drinkID")]
    drink_id: Option<Id>,
}

// MARK: Export

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ExportDrink {
    pub id: String,
    pub name: String,
    pub category: String,
    pub abv: f64,
    pub vessel: String,
    pub volume_ml: f64,
    pub price: f64,
    pub is_generic: bool,
    pub is_hidden: bool,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ExportFavourite {
    pub drink_id: String,
    pub vessel: String,
    pub volume_ml: f64,
    pub price: f64,
    pub sort_order: i64,
}

/// A logged drink, as the app has it: the strength and calories already resolved against its drink.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ExportEntry {
    pub id: String,
    /// Whole seconds since the epoch.
    pub time: i64,
    pub day: i64,
    pub name: String,
    pub category: String,
    pub vessel: String,
    pub volume_ml: f64,
    pub abv: f64,
    pub units: f64,
    pub kcal: f64,
    pub price: f64,
    pub drink_id: String,
}

/// What an export is assembled from. `entries` come in time order.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ExportInput {
    pub exported_at: i64,
    pub rollover_hour: i64,
    pub currency: String,
    /// The app's own encoding of the goal, as a JSON object.
    pub goal_json: Option<String>,
    /// The same goal for the maths: budgets and the stop date.
    pub goal: GoalSpec,
    pub today: i64,
    pub first_weekday: i64,
    pub days: Vec<DayRow>,
    pub entries: Vec<ExportEntry>,
    pub drinks: Vec<ExportDrink>,
    pub favourites: Vec<ExportFavourite>,
}

fn rounded2(value: f64) -> f64 {
    (value * 100.0).round() / 100.0
}

/// Assembles the document for an export.
#[uniffi::export]
pub fn backup_build(input: ExportInput) -> Result<Arc<BackupDoc>, BackupError> {
    let ledger = CoreLedger::new(input.days.clone(), input.today, input.first_weekday);
    let mut by_day: std::collections::HashMap<i64, Vec<&ExportEntry>> = std::collections::HashMap::new();
    for entry in &input.entries {
        by_day.entry(entry.day).or_default().push(entry);
    }
    // Through today, or further where an entry was timed after it, so nothing logged is left out of the file.
    let last = by_day.keys().copied().max().map_or(input.today, |day| day.max(input.today));
    let days: Vec<i64> = match ledger.first_day() {
        Some(first) => (first.min(input.today)..=last).collect(),
        None => Vec::new(),
    };
    let invalid = |what: &str, value: &str| BackupError::Unreadable { reason: format!("{what} {value}") };
    let id = |text: &str| Id::parse(text).ok_or_else(|| invalid("not an id:", text));
    let named = |text: &str, vessel: bool| {
        if if vessel { is_vessel(text) } else { is_category(text) } { Ok(text.to_string()) } else { Err(invalid("unknown name:", text)) }
    };

    let goal = match &input.goal_json {
        Some(text) => Some(serde_json::from_str::<Value>(text).map_err(|e| BackupError::Unreadable { reason: e.to_string() })?),
        None => None,
    };
    let stoppable = goal_projection(input.goal, input.today).stoppable;
    let mut drinks = Vec::new();
    for drink in &input.drinks {
        drinks.push(DrinkRec {
            id: id(&drink.id)?,
            name: drink.name.clone(),
            category: Named(named(&drink.category, false)?),
            abv: drink.abv,
            vessel: Named(named(&drink.vessel, true)?),
            volume_ml: drink.volume_ml,
            price: drink.price,
            is_generic: drink.is_generic,
            is_hidden: drink.is_hidden,
        });
    }
    let mut favourites = Vec::new();
    for favourite in &input.favourites {
        favourites.push(FavouriteRec {
            drink_id: id(&favourite.drink_id)?,
            vessel: Named(named(&favourite.vessel, true)?),
            volume_ml: favourite.volume_ml,
            price: favourite.price,
            order: favourite.sort_order,
        });
    }
    let mut records = Vec::new();
    for day in days.into_iter().rev() {
        let totals = ledger.totals(day);
        let entries = by_day.get(&day).cloned().unwrap_or_default();
        let status = match ledger.status(day) {
            StatusKind::Drank => "drank",
            StatusKind::Future if entries.is_empty() => "not_logged",
            StatusKind::Future => "drank",
            StatusKind::AlcoholFree => "alcohol_free",
            StatusKind::Today => "in_progress",
            _ => "not_logged",
        };
        let mut pours = Vec::new();
        for entry in entries {
            pours.push(PourRec {
                id: Some(id(&entry.id)?),
                time: Some(entry.time),
                name: entry.name.clone(),
                category: Some(Named(named(&entry.category, false)?)),
                vessel: Some(Named(named(&entry.vessel, true)?)),
                volume_ml: Some(entry.volume_ml),
                abv: Some(entry.abv),
                units: Some(rounded2(entry.units)),
                kcal: Some(entry.kcal.round()),
                price: Some(entry.price),
                drink_id: Some(id(&entry.drink_id)?),
            });
        }
        records.push(DayRec {
            date: day_format(day),
            status: status.to_string(),
            units: Some(rounded2(totals.units)),
            kcal: Some(totals.kcal.round()),
            cost: Some(rounded2(totals.cost)),
            spent_by_hand: ledger.spend_override(day).map(rounded2),
            budget: crate::goal::goal_daily_budget(input.goal, day).map(rounded2),
            pours: Some(pours),
        });
    }
    Ok(Arc::new(BackupDoc {
        doc: Doc {
            format: Some("groglog/1".into()),
            exported_at: Some(input.exported_at),
            notes: Some(NOTES.into()),
            day_starts_at_hour: Some(input.rollover_hour),
            currency: Some(input.currency),
            goal,
            projected_stop: stoppable.map(day_format),
            drinks: Some(drinks),
            favourites: Some(favourites),
            days: records,
        },
    }))
}

// MARK: Restore

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SnapshotDrink {
    pub id: String,
    pub name: String,
    pub category: String,
    pub abv: f64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SnapshotFavourite {
    pub drink_id: String,
    pub vessel: String,
    pub volume_ml: f64,
}

/// What a restore needs to know about the log it is merging into. `drinks` are in storage order, since a drink is
/// found by name and kind and the first one wins. `today` is the current drinking day under the file's day end.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RestoreSnapshot {
    pub today: i64,
    pub drinks: Vec<SnapshotDrink>,
    pub favourites: Vec<SnapshotFavourite>,
    pub pour_ids: Vec<String>,
    pub days_with_pours: Vec<i64>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum RestoreOp {
    InsertDrink {
        id: String,
        name: String,
        category: String,
        abv: f64,
        vessel: String,
        volume_ml: f64,
        price: f64,
        is_generic: bool,
        is_hidden: bool,
        sort_order: i64,
    },
    InsertFavourite { drink_id: String, vessel: String, volume_ml: f64, price: f64, sort_order: i64 },
    MarkAlcoholFree { day: i64 },
    SetSpend { day: i64, amount: f64 },
    /// `time` is absent for a drink the file gives no time for; it goes `evening_offset_minutes` after the evening of
    /// its day, which the app works out in its own calendar.
    InsertPour {
        id: String,
        drink_id: String,
        time: Option<i64>,
        evening_offset_minutes: i64,
        day: i64,
        vessel: String,
        volume_ml: f64,
        price: f64,
        kcal_override: Option<f64>,
        abv_override: Option<f64>,
    },
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RestorePlan {
    pub ops: Vec<RestoreOp>,
    /// How many entries the plan adds.
    pub added: i64,
    /// The days whose totals need recomputing once the operations are applied.
    pub touched: Vec<i64>,
}

struct KnownDrink {
    id: Id,
    name: String,
    category: String,
    abv: f64,
}

struct Planner {
    drinks: Vec<KnownDrink>,
    ops: Vec<RestoreOp>,
}

impl Planner {
    fn find(&self, name: &str, category: &str) -> Option<&KnownDrink> {
        self.drinks.iter().find(|drink| drink.name == name && drink.category == category)
    }

    fn by_id(&self, id: &Id) -> Option<&KnownDrink> {
        self.drinks.iter().find(|drink| drink.id == *id)
    }

    fn create(&mut self, drink: KnownDrink, vessel: &str, volume_ml: f64, is_generic: bool, sort_order: i64) -> Id {
        self.ops.push(RestoreOp::InsertDrink {
            id: drink.id.0.clone(),
            name: drink.name.clone(),
            category: drink.category.clone(),
            abv: drink.abv,
            vessel: vessel.to_string(),
            volume_ml,
            price: 0.0,
            is_generic,
            is_hidden: false,
            sort_order,
        });
        let id = drink.id.clone();
        self.drinks.push(drink);
        id
    }

    /// A drink by name and kind, made if there is none.
    fn find_or_create(&mut self, name: &str, category: &str, abv: f64, vessel: &str, volume_ml: f64) -> Id {
        if let Some(drink) = self.find(name, category) {
            return drink.id.clone();
        }
        self.create(KnownDrink { id: Id::random(), name: name.to_string(), category: category.to_string(), abv }, vessel, volume_ml, false, 0)
    }

    /// The drink bare unit counts are logged against, made if there is none.
    fn units_drink(&mut self) -> Id {
        if let Some(drink) = self.drinks.iter().find(|drink| drink.category == "units") {
            return drink.id.clone();
        }
        self.create(KnownDrink { id: Id::random(), name: "Units".into(), category: "units".into(), abv: 100.0 }, "shot", 10.0, true, 99)
    }
}

// MARK: Markdown

/// How the app writes numbers and dates for a reader, in its own locale.
#[uniffi::export(with_foreign)]
pub trait MarkdownFormat: Send + Sync {
    fn units(&self, value: f64) -> String;
    fn money(&self, value: f64, currency: String) -> String;
    fn volume(&self, ml: f64) -> String;
    fn abv(&self, abv: f64) -> String;
    /// An abbreviated date with a shortened time.
    fn date_time(&self, seconds: i64) -> String;
    fn date(&self, seconds: i64) -> String;
    fn time(&self, seconds: i64) -> String;
}

#[derive(uniffi::Object)]
pub struct BackupDoc {
    doc: Doc,
}

#[uniffi::export]
impl BackupDoc {
    /// Reads a backup. Refused for a file that is not one, or that sets the day to end at an hour that is not one.
    #[uniffi::constructor]
    pub fn parse(data: Vec<u8>) -> Result<Arc<Self>, BackupError> {
        let doc: Doc = serde_json::from_slice(&data).map_err(|error| BackupError::Unreadable { reason: error.to_string() })?;
        // An hour outside 0-23 would break every date the clock builds, so the file is refused.
        if let Some(hour) = doc.day_starts_at_hour.filter(|hour| !(0..=23).contains(hour)) {
            return Err(BackupError::DayEndsAtImpossibleHour { hour });
        }
        Ok(Arc::new(BackupDoc { doc }))
    }

    pub fn day_starts_at_hour(&self) -> Option<i64> {
        self.doc.day_starts_at_hour
    }

    pub fn currency(&self) -> Option<String> {
        self.doc.currency.clone()
    }

    /// The goal as the file holds it, for the app's own codec to read.
    pub fn goal_json(&self) -> Option<String> {
        self.doc.goal.as_ref().map(Value::to_string)
    }

    /// UTF-8 JSON, laid out exactly as iOS lays it out.
    pub fn json(&self) -> Vec<u8> {
        let value = serde_json::to_value(&self.doc).expect("a backup is always JSON");
        swift_json::encode(&value).into_bytes()
    }

    /// A compact, readable log meant for pasting into a chat with an LLM. `now` stands in for a missing export time.
    pub fn markdown(&self, now: i64, format: Arc<dyn MarkdownFormat>) -> String {
        let doc = &self.doc;
        let currency = doc.currency.clone().unwrap_or_else(|| "GBP".into());
        let money = |value: Option<f64>| format.money(value.unwrap_or(0.0), currency.clone());
        let mut lines = vec![
            "# Drinking log".to_string(),
            String::new(),
            format!("Exported {}. {}", format.date_time(doc.exported_at.unwrap_or(now)), doc.notes.clone().unwrap_or_default()),
            String::new(),
        ];
        if let Some(goal) = doc.goal.as_ref().filter(|goal| goal.get("isEnabled").and_then(Value::as_bool) == Some(true)) {
            let number = |key: &str, default: f64| goal.get(key).and_then(Value::as_f64).unwrap_or(default);
            let start = goal.get("start").and_then(Value::as_str).and_then(iso::parse);
            let from = format!(
                "from {} units/week starting {}",
                format.units(number("baselineWeekly", 28.0)),
                start.map(|seconds| format.date(seconds)).unwrap_or_default()
            );
            let target = format.units(number("targetWeekly", 0.0));
            let period = number("periodDays", 4.0) as i64;
            lines.push(match goal.get("taper").and_then(Value::as_str).unwrap_or("dynamic") {
                "proportional" => format!(
                    "Goal: cut {}% every {period} day(s), compounding daily, down to {target} units/week, on a fixed schedule {from}.",
                    number("reductionPercent", 10.0) as i64
                ),
                "linear" => format!(
                    "Goal: cut {} units/day off the daily budget every {period} day(s), down to {target} units/week, on a fixed schedule {from}.",
                    format.units(number("reductionUnits", 1.0))
                ),
                _ => format!("Goal: stepped taper, cut 10% every 4 days above 25 units/day, every 3 days above 15, then every day, compounding daily, down to {target} units/week, on a fixed schedule {from}."),
            });
            if let Some(stop) = &doc.projected_stop {
                lines.push(format!("At this rate: down to {} units/week, low enough to stop, by {stop}.", format.units(STOP_FROM)));
            }
            lines.push(String::new());
        }
        lines.push("## Days (newest first)".into());
        lines.push(String::new());
        for day in &doc.days {
            match day.status.as_str() {
                "alcohol_free" => lines.push(format!("- {}: alcohol-free", day.date)),
                "not_logged" => lines.push(format!("- {}: not logged", day.date)),
                status => {
                    let budget = day.budget.map(|budget| format!(" (budget {})", format.units(budget))).unwrap_or_default();
                    let so_far = if status == "in_progress" { " (so far)" } else { "" };
                    lines.push(format!(
                        "- {}: {} u{budget}, {} kcal, {}{so_far}",
                        day.date,
                        format.units(day.units.unwrap_or(0.0)),
                        day.kcal.unwrap_or(0.0) as i64,
                        money(day.cost)
                    ));
                    for pour in day.pours.iter().flatten() {
                        let at = pour.time.map(|seconds| format.time(seconds)).unwrap_or_default();
                        lines.push(format!(
                            "  - {at} {}, {} at {}: {} u",
                            pour.name,
                            format.volume(pour.volume_ml.unwrap_or(0.0)),
                            format.abv(pour.abv.unwrap_or(0.0)),
                            format.units(pour.units.unwrap_or(0.0))
                        ));
                    }
                }
            }
        }
        lines.join("\n")
    }

    /// Merges the file into the log described by `snapshot` without modifying existing data: drinks and entries are
    /// matched by id, and a day that already has drinks keeps them. The operations come in the order to apply them.
    pub fn plan(&self, snapshot: RestoreSnapshot) -> RestorePlan {
        let mut planner = Planner {
            drinks: snapshot
                .drinks
                .iter()
                .map(|d| KnownDrink { id: Id::parse(&d.id).unwrap_or_else(|| Id(d.id.to_uppercase())), name: d.name.clone(), category: d.category.clone(), abv: d.abv })
                .collect(),
            ops: Vec::new(),
        };
        let canonical = |text: &str| Id::parse(text).unwrap_or_else(|| Id(text.to_uppercase())).0;
        let mut pinned: HashSet<(String, String, u64)> =
            snapshot.favourites.iter().map(|f| (canonical(&f.drink_id), f.vessel.clone(), f.volume_ml.to_bits())).collect();
        // A pour already logged, or listed earlier in the same file, is kept as it is: the first copy wins.
        let mut existing_pours: HashSet<String> = snapshot.pour_ids.iter().map(|id| canonical(id)).collect();
        let days_with_pours: HashSet<i64> = snapshot.days_with_pours.iter().copied().collect();

        // Backup drinks match existing ones by id, or by name and type (a fresh install's generics), so restoring onto
        // a new device does not duplicate every drink.
        let mut drink_ids: std::collections::HashMap<Id, Id> = std::collections::HashMap::new();
        for record in self.doc.drinks.iter().flatten() {
            let existing = planner.by_id(&record.id).or_else(|| planner.find(&record.name, &record.category.0)).map(|d| d.id.clone());
            match existing {
                Some(id) => {
                    drink_ids.insert(record.id.clone(), id);
                }
                None => {
                    planner.create(
                        KnownDrink { id: record.id.clone(), name: record.name.clone(), category: record.category.0.clone(), abv: record.abv },
                        &record.vessel.0,
                        record.volume_ml,
                        record.is_generic,
                        0,
                    );
                    // The record's own price, strength and visibility, not the defaults `create` writes.
                    if let Some(RestoreOp::InsertDrink { price, is_hidden, .. }) = planner.ops.last_mut() {
                        *price = record.price;
                        *is_hidden = record.is_hidden;
                    }
                    drink_ids.insert(record.id.clone(), record.id.clone());
                }
            }
        }
        for record in self.doc.favourites.iter().flatten() {
            let Some(drink_id) = drink_ids.get(&record.drink_id) else { continue };
            if pinned.insert((drink_id.0.clone(), record.vessel.0.clone(), record.volume_ml.to_bits())) {
                planner.ops.push(RestoreOp::InsertFavourite {
                    drink_id: drink_id.0.clone(),
                    vessel: record.vessel.0.clone(),
                    volume_ml: record.volume_ml,
                    price: record.price,
                    sort_order: record.order,
                });
            }
        }

        let mut added = 0;
        let mut touched: std::collections::BTreeSet<i64> = std::collections::BTreeSet::new();
        for record in &self.doc.days {
            let Some(day) = day_parse(record.date.clone()) else { continue };
            if days_with_pours.contains(&day) {
                continue;
            }
            // Only entries are taken from a day after today, as the backup gives them: a future day cannot be marked
            // dry or given a spend, and a bare total for one would put the log's first day after today.
            let future = day > snapshot.today;
            if !future && record.status == "alcohol_free" {
                planner.ops.push(RestoreOp::MarkAlcoholFree { day });
            }
            if !future && let Some(amount) = record.spent_by_hand {
                planner.ops.push(RestoreOp::SetSpend { day, amount });
                touched.insert(day);
            }
            let pours = record.pours.as_deref().unwrap_or_default();
            if !future && pours.is_empty() && let Some(units) = record.units.filter(|units| *units > 0.0) {
                let drink = planner.units_drink();
                planner.ops.push(RestoreOp::InsertPour {
                    id: Id::random().0,
                    drink_id: drink.0,
                    time: None,
                    evening_offset_minutes: 0,
                    day,
                    vessel: "shot".into(),
                    volume_ml: units * 10.0,
                    price: record.cost.unwrap_or(0.0),
                    kcal_override: record.kcal,
                    abv_override: None,
                });
                added += 1;
                touched.insert(day);
            }
            for (index, pour) in pours.iter().enumerate() {
                if let Some(id) = &pour.id && !existing_pours.insert(id.0.clone()) {
                    continue;
                }
                let id = pour.id.clone().unwrap_or_else(Id::random);
                let offset = index as i64 * 30;
                if let Some(volume) = pour.volume_ml {
                    let category = pour.category.as_ref().map_or("beer", |c| c.0.as_str());
                    let vessel = pour.vessel.as_ref().map_or_else(|| default_vessel(category).to_string(), |v| v.0.clone());
                    let mapped = pour.drink_id.as_ref().and_then(|id| drink_ids.get(id)).and_then(|id| planner.by_id(id)).map(|d| d.id.clone());
                    let drink_id = mapped.unwrap_or_else(|| {
                        planner.find_or_create(&pour.name, category, pour.abv.unwrap_or_else(|| default_abv(category)), &vessel, volume)
                    });
                    let drink = planner.by_id(&drink_id).expect("the drink was just found or made");
                    let kcal = if drink.category == "units" { pour.kcal } else { None };
                    let abv = pour.abv.filter(|abv| *abv != drink.abv);
                    planner.ops.push(RestoreOp::InsertPour {
                        id: id.0,
                        drink_id: drink_id.0,
                        time: pour.time,
                        evening_offset_minutes: offset,
                        day,
                        vessel,
                        volume_ml: volume,
                        price: pour.price.unwrap_or(0.0),
                        kcal_override: kcal,
                        abv_override: abv,
                    });
                } else {
                    let drink = planner.units_drink();
                    planner.ops.push(RestoreOp::InsertPour {
                        id: id.0,
                        drink_id: drink.0,
                        time: pour.time,
                        evening_offset_minutes: offset,
                        day,
                        vessel: "shot".into(),
                        volume_ml: pour.units.unwrap_or(0.0) * 10.0,
                        price: pour.price.unwrap_or(0.0),
                        kcal_override: pour.kcal,
                        abv_override: None,
                    });
                }
                added += 1;
                touched.insert(day);
            }
        }
        RestorePlan { ops: planner.ops, added, touched: touched.into_iter().collect() }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::days::day_number;

    const IOS: &[u8] = include_bytes!("../../android/app/src/test/resources/ios-backup.json");
    const MINIMAL: &[u8] = include_bytes!("../tests/backup/daily-totals.json");
    const WITH_DRINKS: &[u8] = include_bytes!("../tests/backup/with-drinks.json");

    fn parse(data: &[u8]) -> Arc<BackupDoc> {
        BackupDoc::parse(data.to_vec()).expect("a readable backup")
    }

    fn snapshot(today: i64) -> RestoreSnapshot {
        RestoreSnapshot { today, drinks: vec![], favourites: vec![], pour_ids: vec![], days_with_pours: vec![] }
    }

    /// Applies a plan to a snapshot as the apps' databases would, so a second restore sees the first.
    fn apply(plan: &RestorePlan, snapshot: &mut RestoreSnapshot) {
        for op in &plan.ops {
            match op {
                RestoreOp::InsertDrink { id, name, category, abv, .. } => {
                    snapshot.drinks.push(SnapshotDrink { id: id.clone(), name: name.clone(), category: category.clone(), abv: *abv })
                }
                RestoreOp::InsertFavourite { drink_id, vessel, volume_ml, .. } => snapshot.favourites.push(SnapshotFavourite {
                    drink_id: drink_id.clone(),
                    vessel: vessel.clone(),
                    volume_ml: *volume_ml,
                }),
                RestoreOp::InsertPour { id, day, .. } => {
                    snapshot.pour_ids.push(id.clone());
                    snapshot.days_with_pours.push(*day);
                }
                _ => {}
            }
        }
    }

    struct Plain;

    impl MarkdownFormat for Plain {
        fn units(&self, value: f64) -> String {
            format!("{value:.1}")
        }
        fn money(&self, value: f64, currency: String) -> String {
            format!("{currency} {value:.2}")
        }
        fn volume(&self, ml: f64) -> String {
            format!("{ml} ml")
        }
        fn abv(&self, abv: f64) -> String {
            format!("{abv}%")
        }
        fn date_time(&self, seconds: i64) -> String {
            iso::format(seconds)
        }
        fn date(&self, seconds: i64) -> String {
            iso::format(seconds)[..10].to_string()
        }
        fn time(&self, seconds: i64) -> String {
            iso::format(seconds)[11..16].to_string()
        }
    }

    #[test]
    fn a_backup_written_by_ios_is_written_back_byte_for_byte() {
        assert_eq!(parse(IOS).json(), IOS);
    }

    #[test]
    fn dates_read_with_offsets_and_write_in_utc() {
        assert_eq!(iso::parse("2026-09-13T19:05:00+01:00").map(iso::format).as_deref(), Some("2026-09-13T18:05:00Z"));
        assert_eq!(iso::parse("2026-09-13T19:05:00.250Z").map(iso::format).as_deref(), Some("2026-09-13T19:05:00Z"));
        assert_eq!(iso::parse("1969-12-31T23:59:59Z"), Some(-1));
        // A damaged offset is refused rather than sliced through a multi-byte character.
        for bad in ["2026-09-13", "2026-09-13T19:05:00", "2026-13-13T19:05:00Z", "2026-02-30T19:05:00Z", "nonsense", "", "2026-09-13T19:05:00+0éa", "2026-09-13T19:05:00+é", "2026-09-13T19:05:00+01:0é"] {
            assert_eq!(iso::parse(bad), None, "{bad}");
        }
    }

    #[test]
    fn a_file_that_is_not_a_backup_is_refused() {
        for bad in [&b"not json"[..], br#"{"drinks": []}"#, br#"{"days": [{"date": "2026-09-11"}]}"#, br#"{"days": [{"date": "2026-09-11", "status": 3}]}"#] {
            assert!(matches!(BackupDoc::parse(bad.to_vec()), Err(BackupError::Unreadable { .. })), "{}", String::from_utf8_lossy(bad));
        }
        assert!(matches!(BackupDoc::parse(br#"{"dayStartsAtHour": 24, "days": []}"#.to_vec()), Err(BackupError::DayEndsAtImpossibleHour { hour: 24 })));
        assert!(BackupDoc::parse(br#"{"dayStartsAtHour": 23, "days": []}"#.to_vec()).is_ok());
        let unknown_category = br#"{"days": [{"date": "2026-09-11", "status": "drank", "pours": [{"name": "x", "category": "mead"}]}]}"#;
        assert!(BackupDoc::parse(unknown_category.to_vec()).is_err());
        let bad_id = br#"{"drinks": [{"id": "nope", "name": "x", "category": "beer", "abv": 4, "vessel": "pint", "volumeMl": 568, "price": 1, "isGeneric": false, "isHidden": false}], "days": []}"#;
        assert!(BackupDoc::parse(bad_id.to_vec()).is_err());
    }

    #[test]
    fn only_the_date_and_status_are_required_and_other_fields_are_ignored() {
        let doc = parse(br#"{"unknown": 1, "days": [{"date": "2026-09-11", "status": "alcohol_free", "extra": [1]}]}"#);
        assert_eq!(doc.day_starts_at_hour(), None);
        assert_eq!(doc.currency(), None);
        assert_eq!(doc.goal_json(), None);
    }

    #[test]
    fn the_settings_and_goal_come_out_as_the_file_has_them() {
        let doc = parse(IOS);
        assert_eq!((doc.day_starts_at_hour(), doc.currency().as_deref()), (Some(5), Some("GBP")));
        let goal: Value = serde_json::from_str(&doc.goal_json().unwrap()).unwrap();
        assert_eq!(goal["taper"], "linear");
        assert_eq!(goal["start"], "2026-09-01T04:00:00Z");
    }

    #[test]
    fn restoring_the_ios_backup_adds_its_drinks_favourites_and_pours() {
        let today = day_number(2026, 10, 12);
        let plan = parse(IOS).plan(snapshot(today));
        assert_eq!(plan.added, 3);
        assert_eq!(plan.touched, vec![day_number(2026, 10, 8), day_number(2026, 10, 11)]);
        let drinks = plan.ops.iter().filter(|op| matches!(op, RestoreOp::InsertDrink { .. })).count();
        assert_eq!(drinks, 3, "the two drinks in the file, and one the Units pour makes because it names none");
        assert!(plan.ops.iter().any(|op| matches!(op, RestoreOp::MarkAlcoholFree { day } if *day == day_number(2026, 10, 10))));
        assert!(plan.ops.iter().any(|op| matches!(op, RestoreOp::SetSpend { day, amount } if *day == day_number(2026, 10, 11) && *amount == 20.0)));
        let glass = plan
            .ops
            .iter()
            .find_map(|op| match op {
                RestoreOp::InsertPour { id, abv_override, time, .. } if id == "C3E85A12-7B9F-4D21-A06E-2F4B8D17C590" => Some((*abv_override, *time)),
                _ => None,
            })
            .expect("the rosé is planned");
        assert_eq!(glass.0, Some(13.6), "logged at its own strength");
        assert_eq!(glass.1, iso::parse("2026-10-11T21:40:00Z"));
        // The Units pour carries its calories, since its drink is a count of units.
        assert!(plan.ops.iter().any(|op| matches!(op, RestoreOp::InsertDrink { category, .. } if category == "units")));
        assert!(plan.ops.iter().any(|op| matches!(op, RestoreOp::InsertPour { kcal_override: Some(k), .. } if *k == 1e21)));
    }

    #[test]
    fn restoring_twice_adds_nothing_the_second_time() {
        let today = day_number(2026, 10, 12);
        let mut state = snapshot(today);
        let doc = parse(IOS);
        let first = doc.plan(state.clone());
        apply(&first, &mut state);
        let second = doc.plan(state.clone());
        assert_eq!((first.added, second.added), (3, 0));
        assert!(second.ops.iter().all(|op| !matches!(op, RestoreOp::InsertPour { .. } | RestoreOp::InsertDrink { .. } | RestoreOp::InsertFavourite { .. })));
    }

    #[test]
    fn a_fresh_installs_generics_are_matched_by_name_and_kind() {
        let doc = parse(IOS);
        let mut state = snapshot(day_number(2026, 10, 12));
        state.drinks.push(SnapshotDrink { id: "AAAAAAAA-0000-4000-8000-000000000001".into(), name: "Beer".into(), category: "beer".into(), abv: 4.0 });
        let plan = doc.plan(state);
        assert!(plan.ops.iter().all(|op| !matches!(op, RestoreOp::InsertDrink { name, .. } if name == "Beer")), "the existing Beer is reused");
        let pour = plan.ops.iter().find_map(|op| match op {
            RestoreOp::InsertPour { id, drink_id, .. } if id == "9F1D3B57-2C8A-4E06-B7D4-61A0E5C93F28" => Some(drink_id.clone()),
            _ => None,
        });
        assert_eq!(pour.as_deref(), Some("AAAAAAAA-0000-4000-8000-000000000001"));
        let favourite = plan.ops.iter().find_map(|op| match op {
            RestoreOp::InsertFavourite { drink_id, .. } => Some(drink_id.clone()),
            _ => None,
        });
        assert_eq!(favourite.as_deref(), Some("AAAAAAAA-0000-4000-8000-000000000001"), "pinned against the drink it matched");
    }

    #[test]
    fn a_dry_day_leaves_a_spend_set_by_hand_alone() {
        let plan = parse(br#"{"days": [{"date": "2026-09-11", "status": "alcohol_free"}]}"#).plan(snapshot(day_number(2026, 9, 20)));
        assert_eq!(plan.ops, vec![RestoreOp::MarkAlcoholFree { day: day_number(2026, 9, 11) }]);
        assert!(plan.touched.is_empty());
    }

    #[test]
    fn daily_totals_become_one_units_entry_each() {
        let today = day_number(2026, 9, 20);
        let plan = parse(MINIMAL).plan(snapshot(today));
        assert_eq!(plan.added, 1);
        let pour = plan.ops.iter().find_map(|op| match op {
            RestoreOp::InsertPour { day, volume_ml, price, kcal_override, vessel, time, evening_offset_minutes, .. } => {
                Some((*day, *volume_ml, *price, *kcal_override, vessel.clone(), *time, *evening_offset_minutes))
            }
            _ => None,
        });
        assert_eq!(pour, Some((day_number(2026, 9, 12), 306.0, 42.0, Some(2696.0), "shot".into(), None, 0)));
        assert!(plan.ops.iter().any(|op| matches!(op, RestoreOp::MarkAlcoholFree { day } if *day == day_number(2026, 9, 11))));
    }

    #[test]
    fn drinks_without_a_time_are_spaced_half_an_hour_apart() {
        let plan = parse(WITH_DRINKS).plan(snapshot(day_number(2026, 9, 20)));
        assert_eq!(plan.added, 2);
        let pours: Vec<(Option<i64>, i64, String, f64, Option<f64>)> = plan
            .ops
            .iter()
            .filter_map(|op| match op {
                RestoreOp::InsertPour { time, evening_offset_minutes, vessel, volume_ml, abv_override, .. } => {
                    Some((*time, *evening_offset_minutes, vessel.clone(), *volume_ml, *abv_override))
                }
                _ => None,
            })
            .collect();
        assert_eq!(pours[0].0, iso::parse("2026-09-13T19:05:00+01:00"));
        assert_eq!((pours[1].0, pours[1].1), (None, 30));
        // The pour with no vessel takes its kind's, and each is a drink of its own, made as it is met.
        assert_eq!(pours[1].2, "bottle");
        assert_eq!(plan.ops.iter().filter(|op| matches!(op, RestoreOp::InsertDrink { .. })).count(), 2);
    }

    #[test]
    fn a_future_day_takes_its_entries_but_not_marks_or_totals() {
        let today = day_number(2026, 9, 20);
        let file = br#"{"days": [
            {"date": "2026-09-21", "status": "alcohol_free", "spentByHand": 5, "units": 3},
            {"date": "2026-09-22", "status": "drank", "pours": [{"name": "Beer", "category": "beer", "volumeMl": 568, "abv": 4}]}
        ]}"#;
        let plan = parse(file).plan(snapshot(today));
        assert_eq!(plan.added, 1);
        assert!(plan.ops.iter().all(|op| !matches!(op, RestoreOp::MarkAlcoholFree { .. } | RestoreOp::SetSpend { .. })));
        assert_eq!(plan.touched, vec![day_number(2026, 9, 22)]);
    }

    #[test]
    fn a_day_that_already_has_drinks_keeps_them_and_a_repeated_id_in_the_file_counts_once() {
        let today = day_number(2026, 9, 20);
        let id = "9F1D3B57-2C8A-4E06-B7D4-61A0E5C93F28";
        let file = format!(
            r#"{{"days": [
                {{"date": "2026-09-10", "status": "drank", "pours": [{{"name": "Beer", "volumeMl": 568}}]}},
                {{"date": "2026-09-11", "status": "drank", "pours": [{{"id": "{id}", "name": "Beer", "volumeMl": 568}}, {{"id": "{}", "name": "Beer", "volumeMl": 568}}]}}
            ]}}"#,
            id.to_lowercase()
        );
        let mut state = snapshot(today);
        state.days_with_pours.push(day_number(2026, 9, 10));
        let plan = parse(file.as_bytes()).plan(state);
        assert_eq!(plan.added, 1);
        assert_eq!(plan.touched, vec![day_number(2026, 9, 11)]);
    }

    #[test]
    fn an_export_assembles_reads_back_and_restores_to_the_same_log() {
        let today = day_number(2026, 10, 12);
        let pint = 568.0 * 4.0 / 1000.0;
        let input = ExportInput {
            exported_at: iso::parse("2026-10-12T09:30:00Z").unwrap(),
            rollover_hour: 5,
            currency: "GBP".into(),
            goal_json: Some(r#"{"isEnabled":false,"taper":"dynamic"}"#.into()),
            goal: GoalSpec {
                is_enabled: false,
                taper: crate::goal::TaperKind::Dynamic,
                baseline_weekly: 28.0,
                reduction_percent: 10.0,
                reduction_units: 1.0,
                period_days: 4,
                start_day: 0,
                target_weekly: 0.0,
            },
            today,
            first_weekday: 2,
            days: vec![
                DayRow { number: today - 1, is_alcohol_free: false, units: pint, kcal: 182.4, cost: 6.4, count: 1, cost_override: None },
                DayRow { number: today - 2, is_alcohol_free: true, units: 0.0, kcal: 0.0, cost: 0.0, count: 0, cost_override: Some(12.0) },
            ],
            entries: vec![ExportEntry {
                id: "9F1D3B57-2C8A-4E06-B7D4-61A0E5C93F28".into(),
                time: iso::parse("2026-10-11T19:05:42Z").unwrap(),
                day: today - 1,
                name: "Beer".into(),
                category: "beer".into(),
                vessel: "pint".into(),
                volume_ml: 568.0,
                abv: 4.0,
                units: pint,
                kcal: 182.4,
                price: 6.4,
                drink_id: "5E2A7C91-0D34-4B6F-8E12-A9C4F07B3D65".into(),
            }],
            drinks: vec![ExportDrink {
                id: "5E2A7C91-0D34-4B6F-8E12-A9C4F07B3D65".into(),
                name: "Beer".into(),
                category: "beer".into(),
                abv: 4.0,
                vessel: "pint".into(),
                volume_ml: 568.0,
                price: 6.4,
                is_generic: true,
                is_hidden: false,
            }],
            favourites: vec![],
        };
        let doc = backup_build(input).unwrap();
        let json = doc.json();
        let read = parse(&json);
        assert_eq!(read.json(), json, "what it writes it reads back unchanged");
        let value: Value = serde_json::from_slice(&json).unwrap();
        let days = value["days"].as_array().unwrap();
        assert_eq!(days.iter().map(|d| d["date"].as_str().unwrap()).collect::<Vec<_>>(), ["2026-10-12", "2026-10-11", "2026-10-10"], "newest first, through today");
        assert_eq!(days[0]["status"], "in_progress");
        assert_eq!(days[1]["units"], 2.27, "rounded to two places");
        assert_eq!(days[1]["kcal"], 182.0);
        assert_eq!(days[2]["status"], "alcohol_free");
        assert_eq!(days[2]["spentByHand"], 12.0);
        assert_eq!(value["format"], "groglog/1");
        let plan = read.plan(snapshot(today));
        assert_eq!(plan.added, 1);
    }

    #[test]
    fn markdown_lists_the_goal_and_each_day() {
        let text = parse(IOS).markdown(0, Arc::new(Plain));
        assert!(text.starts_with("# Drinking log\n\nExported 2026-10-12T09:30:00Z. UK units"));
        assert!(text.contains("Goal: cut 1.5 units/day off the daily budget every 3 day(s), down to 14.0 units/week, on a fixed schedule from 52.5 units/week starting 2026-09-01."));
        assert!(text.contains("At this rate: down to 70.0 units/week, low enough to stop, by 2026-10-20."));
        assert!(text.contains("- 2026-10-12: 0.0 u (budget 7.1), 0 kcal, GBP 0.00 (so far)"));
        assert!(text.contains("- 2026-10-10: alcohol-free"));
        assert!(text.contains("- 2026-10-09: not logged"));
        assert!(text.contains("  - 19:05 Beer, 568 ml at 4%: 2.3 u"));
    }
}
