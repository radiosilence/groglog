//! The drink catalogue: common UK drinks and their usual serves, so logging a specific brand is a search and a tap, and
//! the generic drinks a fresh install starts with. The table is in `catalog_data.rs`; this module merges it into
//! brands and answers the lookups the apps make.
//!
//! The apps hold drinks by name and kind, so a name, category, strength, size or price changing here changes what a
//! logged drink resolves to. Names are an identity, not a label.

use std::{collections::HashMap, sync::OnceLock};

use unicode_normalization::{UnicodeNormalization, char::is_combining_mark};

use crate::categories::{CategoryKind, VesselKind};
use crate::{catalog_data::ENTRIES, rates};

/// A vessel at a volume: a size a drink comes in.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Size {
    vessel: VesselKind,
    ml: f64,
}

impl Size {
    pub(crate) const fn new(vessel: VesselKind, ml: f64) -> Size {
        Size { vessel, ml }
    }
}

type Serve = (Size, f64);

/// A row of the table, priced in pounds.
pub(crate) struct Entry {
    name: &'static str,
    category: CategoryKind,
    abv: f64,
    serves: &'static [Serve],
}

pub(crate) const fn e(name: &'static str, category: CategoryKind, abv: f64, serves: &'static [Serve]) -> Entry {
    Entry { name, category, abv, serves }
}

/// Drinks priced in the market where they are usually bought, one block per currency. A drink also in the main table
/// takes these as its home prices alongside its pounds, so it must have the same strength; a different strength
/// requires a different name.
static MARKETS: &[(&str, &[Entry])] = &[];

/// A brand across every market that lists it. A drink sold abroad is priced in the market where it is usually bought,
/// in that market's currency, and also in pounds where it is sold in the UK.
///
/// Each usual size carries its typical cost: a London bar price for a pint, glass or measure, and a supermarket single
/// price for a can or bottle. Two kinds of figure are estimates rather than lookups. Pubs price draught and
/// by-the-glass by tier rather than by brand, and per-venue prices are rarely published, so a brand with no menu of its
/// own takes its tier's price. Mainstream lager and cider are sold only in multipacks, so those carry the multipack's
/// unit rate, roughly half the price of a single can where one is sold. Craft therefore splits two ways: breweries
/// stocked by supermarkets carry the four-pack rate, and those sold only by bottle shops carry the single-can price,
/// which is why a Camden Hells costs a third of a Verdant. Craft pints are also tiered, banded by strength from the pubs
/// that publish prices: Camden Pale at £6.30, Hepcat and Gamma Ray at £6.90, Camden Hells and Punk IPA at £7.05, Elvis
/// Juice at £7.50. Individual pubs vary by about a pound either way; the figure is a starting price that the user can
/// edit.
///
/// ABVs are the UK label figures. A brand brewed at two strengths is two entries (cask London Pride is 4.1%, the bottle
/// 4.7%), because a drink has one strength and rounding the difference away misstates a unit a night. Brands change
/// strength without notice (the 3.5% duty threshold has pulled many lagers down to 3.4%), so anything logged from here
/// becomes an editable drink of the user's own.
struct Brand {
    name: &'static str,
    category: CategoryKind,
    abv: f64,
    /// Pounds first, then the other markets by currency code.
    markets: Vec<(&'static str, Vec<Serve>)>,
}

impl Brand {
    /// Every size any market lists it in, the UK's first.
    fn sizes(&self) -> Vec<Size> {
        let mut seen: Vec<Size> = Vec::new();
        for (_, serves) in &self.markets {
            for (size, _) in serves {
                if !seen.contains(size) {
                    seen.push(*size);
                }
            }
        }
        seen
    }

    /// A size the brand is not listed in scales from the nearest serve of the same vessel first: a 440 ml bottle is
    /// the 330's price plus a third, not a pint's less a fifth. Draught and packaged prices are not proportional to
    /// each other.
    ///
    /// A drink sold in `currency`'s market is priced from that market alone. Otherwise it is converted from wherever it
    /// is priced, the UK first, at the bundled rates.
    fn price(&self, vessel: VesselKind, ml: f64, currency: &str) -> f64 {
        if let Some((_, serves)) = self.markets.iter().find(|(code, _)| *code == currency) {
            return serves_price(serves, vessel, ml);
        }
        self.markets
            .iter()
            .find_map(|(source, serves)| rates::convert(serves_price(serves, vessel, ml), source, currency))
            .unwrap_or(0.0)
    }
}

fn serves_price(serves: &[Serve], vessel: VesselKind, ml: f64) -> f64 {
    if let Some((_, price)) = serves.iter().find(|(size, _)| size.vessel == vessel && size.ml == ml) {
        return *price;
    }
    let nearest = serves
        .iter()
        .filter(|(size, _)| size.vessel == vessel)
        .min_by(|a, b| (a.0.ml - ml).abs().total_cmp(&(b.0.ml - ml).abs()))
        .or(serves.first());
    match nearest {
        Some((size, price)) => price * ml / size.ml,
        None => 0.0,
    }
}

/// One brand in one of its usual sizes.
struct Item {
    brand: usize,
    size: Size,
}

struct Catalogue {
    brands: Vec<Brand>,
    by_name: HashMap<&'static str, Vec<usize>>,
    items: Vec<Item>,
    /// Search keys, folded once: search runs on every keystroke over a few thousand serves.
    search_keys: Vec<String>,
}

fn catalogue() -> &'static Catalogue {
    static CATALOGUE: OnceLock<Catalogue> = OnceLock::new();
    CATALOGUE.get_or_init(|| {
        let mut brands: Vec<Brand> = Vec::new();
        let mut by_name: HashMap<&'static str, Vec<usize>> = HashMap::new();
        let pounds: (&str, &[Entry]) = ("GBP", ENTRIES);
        for (currency, entries) in std::iter::once(pounds).chain(MARKETS.iter().copied()) {
            for entry in entries {
                let known = by_name.get(entry.name).into_iter().flatten().copied().find(|&i| brands[i].category == entry.category);
                let index = known.unwrap_or_else(|| {
                    brands.push(Brand { name: entry.name, category: entry.category, abv: entry.abv, markets: Vec::new() });
                    by_name.entry(entry.name).or_default().push(brands.len() - 1);
                    brands.len() - 1
                });
                let brand = &mut brands[index];
                assert!(brand.abv == entry.abv, "{} is listed at two strengths", entry.name);
                match brand.markets.iter_mut().find(|(code, _)| *code == currency) {
                    Some((_, serves)) => serves.extend_from_slice(entry.serves),
                    None => brand.markets.push((currency, entry.serves.to_vec())),
                }
            }
        }
        for brand in &mut brands {
            brand.markets.sort_by(|a, b| (a.0 != "GBP", a.0).cmp(&(b.0 != "GBP", b.0)));
        }
        let items: Vec<Item> = brands
            .iter()
            .enumerate()
            .flat_map(|(index, brand)| brand.sizes().into_iter().map(move |size| Item { brand: index, size }))
            .collect();
        let search_keys = items
            .iter()
            .map(|item| {
                let brand = &brands[item.brand];
                fold(&format!("{} {}", brand.name, brand.category.label()))
            })
            .collect();
        Catalogue { brands, by_name, items, search_keys }
    })
}

/// Case and accents folded, so "stella" finds Stella and "kolsch" finds Kölsch.
fn fold(text: &str) -> String {
    text.nfd().filter(|c| !is_combining_mark(*c)).flat_map(char::to_lowercase).collect()
}

fn find(name: &str, category: CategoryKind) -> Option<&'static Brand> {
    let catalogue = catalogue();
    let index = catalogue.by_name.get(name)?.iter().copied().find(|&i| catalogue.brands[i].category == category)?;
    Some(&catalogue.brands[index])
}

/// A generic drink: a kind at its standard strength, with the sizes it is always offered in on the Log grid. Its `id`
/// makes its fixed drink id, the same on every device, so it is kept once given: a new generic takes the next number.
struct Generic {
    id: u8,
    name: &'static str,
    category: CategoryKind,
    serves: &'static [(VesselKind, f64, f64)],
}

/// Generic drinks at Drinkaware's standard strengths. Prices follow the catalogue's convention: a pint, glass or
/// measure at London bar prices, a can or bottle at supermarket prices. All are editable estimates.
static GENERICS: &[Generic] = &[
    Generic {
        id: 1,
        name: "Beer",
        category: CategoryKind::Beer,
        serves: &[
            (VesselKind::Pint, 568.0, 6.40),
            (VesselKind::Half, 284.0, 3.20),
            (VesselKind::Can, 440.0, 2.10),
            (VesselKind::Can, 500.0, 2.40),
            (VesselKind::Bottle, 330.0, 1.95),
            (VesselKind::Bottle, 660.0, 3.15),
        ],
    },
    Generic { id: 2, name: "Stout", category: CategoryKind::Stout, serves: &[(VesselKind::Pint, 568.0, 6.30)] },
    Generic { id: 3, name: "Cider", category: CategoryKind::Cider, serves: &[(VesselKind::Pint, 568.0, 6.50), (VesselKind::Bottle, 500.0, 3.10)] },
    Generic {
        id: 4,
        name: "Red wine",
        category: CategoryKind::RedWine,
        serves: &[(VesselKind::WineGlass, 175.0, 8.50), (VesselKind::WineGlass, 250.0, 12.00), (VesselKind::WineBottle, 750.0, 9.50)],
    },
    Generic {
        id: 5,
        name: "White wine",
        category: CategoryKind::WhiteWine,
        serves: &[(VesselKind::WineGlass, 175.0, 8.50), (VesselKind::WineGlass, 125.0, 6.00)],
    },
    Generic { id: 6, name: "Rosé", category: CategoryKind::Rose, serves: &[(VesselKind::WineGlass, 175.0, 8.50)] },
    Generic { id: 7, name: "Fizz", category: CategoryKind::Bubbles, serves: &[(VesselKind::Flute, 125.0, 8.50), (VesselKind::WineBottle, 750.0, 12.50)] },
    Generic { id: 8, name: "Spirits", category: CategoryKind::Spirit, serves: &[(VesselKind::Shot, 25.0, 5.00)] },
    Generic { id: 9, name: "Alcopop", category: CategoryKind::Alcopop, serves: &[(VesselKind::Bottle, 275.0, 2.20)] },
    Generic { id: 10, name: "Cocktail", category: CategoryKind::Cocktail, serves: &[(VesselKind::Coupe, 150.0, 12.00)] },
    Generic { id: 11, name: "Port or sherry", category: CategoryKind::Fortified, serves: &[(VesselKind::WineGlass, 50.0, 5.50)] },
];

fn generic_price(name: &str, vessel: VesselKind, ml: f64) -> Option<f64> {
    GENERICS
        .iter()
        .find(|generic| generic.name == name)?
        .serves
        .iter()
        .find(|(v, m, _)| *v == vessel && *m == ml)
        .map(|(_, _, price)| *price)
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct SizeRecord {
    pub vessel: VesselKind,
    pub ml: f64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ServeRecord {
    pub vessel: VesselKind,
    pub ml: f64,
    pub price: f64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct MarketRecord {
    pub currency: String,
    pub serves: Vec<ServeRecord>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct BrandRecord {
    pub name: String,
    pub category: CategoryKind,
    pub abv: f64,
    pub markets: Vec<MarketRecord>,
    pub sizes: Vec<SizeRecord>,
}

/// A brand in one of its sizes. `catalog_search` answers with positions in this list, which the caller holds.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ItemRecord {
    pub name: String,
    pub category: CategoryKind,
    pub vessel: VesselKind,
    pub ml: f64,
    pub abv: f64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct GenericRecord {
    /// The drink's id, fixed so a generic logged on two devices is one drink.
    pub id: String,
    pub name: String,
    pub category: CategoryKind,
    pub serves: Vec<ServeRecord>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct LabelRecord {
    pub category: CategoryKind,
    pub label: String,
}

fn size_record(size: &Size) -> SizeRecord {
    SizeRecord { vessel: size.vessel, ml: size.ml }
}

fn serve_record((size, price): &Serve) -> ServeRecord {
    ServeRecord { vessel: size.vessel, ml: size.ml, price: *price }
}

/// Every brand, in catalogue order, for the lists the apps build once.
#[uniffi::export]
pub fn catalog_brands() -> Vec<BrandRecord> {
    catalogue()
        .brands
        .iter()
        .map(|brand| BrandRecord {
            name: brand.name.to_string(),
            category: brand.category,
            abv: brand.abv,
            markets: brand
                .markets
                .iter()
                .map(|(currency, serves)| MarketRecord { currency: currency.to_string(), serves: serves.iter().map(serve_record).collect() })
                .collect(),
            sizes: brand.sizes().iter().map(size_record).collect(),
        })
        .collect()
}

/// Every brand in every size it is listed in, which `catalog_search` indexes.
#[uniffi::export]
pub fn catalog_items() -> Vec<ItemRecord> {
    let catalogue = catalogue();
    catalogue
        .items
        .iter()
        .map(|item| {
            let brand = &catalogue.brands[item.brand];
            ItemRecord {
                name: brand.name.to_string(),
                category: brand.category,
                vessel: item.size.vessel,
                ml: item.size.ml,
                abv: brand.abv,
            }
        })
        .collect()
}

/// The positions in `catalog_items` whose name or kind contains the query, ignoring case and accents. Nothing for an
/// empty query. Positions rather than items, so a short query that matches thousands answers with a few kilobytes.
#[uniffi::export]
pub fn catalog_search(query: String) -> Vec<u32> {
    let folded = fold(query.trim());
    if folded.is_empty() {
        return Vec::new();
    }
    catalogue()
        .search_keys
        .iter()
        .enumerate()
        .filter(|(_, key)| key.contains(&folded))
        .map(|(index, _)| index as u32)
        .collect()
}

/// Whether a drink still matches the catalogue exactly. Changing its name, kind or strength makes it the user's own.
#[uniffi::export]
pub fn catalog_holds(name: String, category: CategoryKind, abv: f64) -> bool {
    find(&name, category).is_some_and(|brand| brand.abv == abv)
}

/// The sizes a drink of this name and kind is listed in, or none for a drink the catalogue does not know.
#[uniffi::export]
pub fn catalog_sizes(name: String, category: CategoryKind) -> Vec<SizeRecord> {
    find(&name, category).map(|brand| brand.sizes().iter().map(size_record).collect()).unwrap_or_default()
}

/// The normal price of a drink of this name in this size: a brand's own price, else a generic's starting price. None
/// when unknown, so callers can distinguish unpriced from free.
#[uniffi::export]
pub fn catalog_price(name: String, category: CategoryKind, vessel: VesselKind, ml: f64, currency: String) -> Option<f64> {
    if let Some(brand) = find(&name, category) {
        let found = brand.price(vessel, ml, &currency);
        return (found > 0.0).then_some(found);
    }
    generic_price(&name, vessel, ml).and_then(|price| rates::convert(price, "GBP", &currency))
}

/// A known brand's price in a size and currency, zero when the brand or the currency is unknown.
#[uniffi::export]
pub fn catalog_brand_price(name: String, category: CategoryKind, vessel: VesselKind, ml: f64, currency: String) -> f64 {
    find(&name, category).map_or(0.0, |brand| brand.price(vessel, ml, &currency))
}

/// A fixed drink id: "grog" in hex, then the number.
fn fixed_id(number: u8) -> String {
    format!("67726F67-0000-4000-8000-{number:012X}")
}

/// The id of the Units drink when it is first made, fixed like the generics' so every device makes the same one.
#[uniffi::export]
pub fn catalog_units_id() -> String {
    fixed_id(0)
}

/// The generic drinks, which the Log grid always offers, and the sizes it offers them in. They are not stored until
/// first logged or pinned, under their fixed ids.
#[uniffi::export]
pub fn catalog_generics() -> Vec<GenericRecord> {
    GENERICS
        .iter()
        .map(|generic| GenericRecord {
            id: fixed_id(generic.id),
            name: generic.name.to_string(),
            category: generic.category,
            serves: generic
                .serves
                .iter()
                .map(|(vessel, ml, price)| ServeRecord { vessel: *vessel, ml: *ml, price: *price })
                .collect(),
        })
        .collect()
}

/// A generic's starting price for a vessel and size, or none when the generic has no such serve.
#[uniffi::export]
pub fn catalog_generic_price(name: String, vessel: VesselKind, ml: f64) -> Option<f64> {
    generic_price(&name, vessel, ml)
}

/// What search matches a kind by. The apps show their own labels, and a test holds the two together.
#[uniffi::export]
pub fn catalog_category_labels() -> Vec<LabelRecord> {
    CategoryKind::ALL
        .iter()
        .map(|category| LabelRecord { category: *category, label: category.label().to_string() })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::rates::{rates_as_of, rates_convert, rates_currencies, rates_per_pound};

    fn kind(raw: &str) -> CategoryKind {
        CategoryKind::parse(raw).unwrap_or_else(|| panic!("no kind {raw}"))
    }

    fn vessel(raw: &str) -> VesselKind {
        VesselKind::parse(raw).unwrap_or_else(|| panic!("no vessel {raw}"))
    }

    fn price(name: &str, category: &str, vessel_raw: &str, ml: f64) -> Option<f64> {
        catalog_price(name.into(), kind(category), vessel(vessel_raw), ml, "GBP".into())
    }

    #[test]
    fn every_brand_is_listed_once_and_has_sizes() {
        let brands = catalog_brands();
        assert_eq!(brands.len(), 1168);
        let mut keys: Vec<_> = brands.iter().map(|b| (b.name.clone(), b.category.raw())).collect();
        keys.sort();
        keys.dedup();
        assert_eq!(keys.len(), brands.len());
        assert!(brands.iter().all(|b| !b.markets.is_empty() && b.markets.iter().all(|m| !m.serves.is_empty()) && !b.sizes.is_empty()));
        let names: std::collections::HashSet<_> = brands.iter().map(|b| &b.name).collect();
        assert_eq!(names.len(), brands.len(), "a name is used in two kinds");
    }

    #[test]
    fn every_item_is_unique_and_plausible() {
        let items = catalog_items();
        let ids: std::collections::HashSet<_> = items.iter().map(|i| format!("{}|{}|{}", i.name, i.vessel.raw(), i.ml as i64)).collect();
        assert_eq!(ids.len(), items.len());
        // The ceiling is a white cider bottle, the one serve that isn't a glassful.
        assert!(items.iter().all(|i| (10.0..=2500.0).contains(&i.ml)));
    }

    /// What a strength can plausibly be for each kind of drink: wide enough for Żywiec Porter, Wray & Nephew and a
    /// 25 ml measure dropped in a glass of Monster, tight enough to catch 45% for 4.5%.
    fn band(category: CategoryKind) -> std::ops::RangeInclusive<f64> {
        match category {
            CategoryKind::Beer | CategoryKind::Stout => 2.0..=13.0,
            CategoryKind::Cider => 2.0..=9.0,
            CategoryKind::RedWine | CategoryKind::WhiteWine | CategoryKind::Rose => 8.0..=16.0,
            CategoryKind::Bubbles => 5.0..=14.0,
            // Down to umeshu and Bulgarian pelin, the fruit and aromatised wines filed alongside vermouth and sake.
            CategoryKind::Fortified => 10.0..=22.0,
            CategoryKind::Spirit => 10.0..=85.0,
            CategoryKind::Alcopop => 3.0..=9.0,
            CategoryKind::Cocktail => 2.0..=35.0,
            CategoryKind::Units => 100.0..=100.0,
        }
    }

    #[test]
    fn strengths_are_plausible_for_their_kind() {
        for brand in catalog_brands() {
            assert!(band(brand.category).contains(&brand.abv), "{} at {}%", brand.name, brand.abv);
        }
    }

    #[test]
    fn search_ignores_case_and_accents_and_matches_kinds() {
        let items = catalog_items();
        let names = |query: &str| -> Vec<String> { catalog_search(query.into()).into_iter().map(|i| items[i as usize].name.clone()).collect() };
        assert!(names("stella").contains(&"Stella Artois".to_string()));
        assert_eq!(names("STELLA"), names("stella"));
        assert_eq!(names("  stella  "), names("stella"));
        assert!(names("rose").contains(&"Thatchers Rosé".to_string()));
        assert_eq!(names("rose"), names("rosé"));
        assert!(catalog_search("   ".into()).is_empty());
        assert!(catalog_search("".into()).is_empty());
        assert!(catalog_search("zzzzzz".into()).is_empty());
        let reds: Vec<_> = catalog_search("Red wine".into()).into_iter().map(|i| items[i as usize].category).collect();
        assert!(!reds.is_empty() && reds.iter().all(|c| *c == CategoryKind::RedWine));
    }

    #[test]
    fn a_brand_is_held_only_while_name_kind_and_strength_match() {
        let stella = catalog_brands().into_iter().find(|b| b.name == "Stella Artois").unwrap();
        assert!(catalog_holds(stella.name.clone(), stella.category, stella.abv));
        assert!(!catalog_holds(stella.name.clone(), stella.category, stella.abv + 0.1));
        assert!(!catalog_holds(format!("{} (the good one)", stella.name), stella.category, stella.abv));
        assert!(!catalog_holds("Dave's shed cider".into(), CategoryKind::Cider, 7.0));
        assert!(!catalog_holds("Beer".into(), CategoryKind::Beer, 4.0), "a generic is the user's own, not the catalogue's");
        assert!(!catalog_holds("Stella Artois".into(), CategoryKind::Cider, stella.abv), "a brand is held under its own kind");
    }

    #[test]
    fn prices_come_from_the_brand_then_the_generic_and_unknowns_are_none() {
        assert!(price("Stella Artois", "beer", "pint", 568.0).unwrap() > 0.0);
        assert_ne!(price("Stella Artois", "beer", "pint", 568.0), price("Beer", "beer", "pint", 568.0));
        assert!(price("Beer", "beer", "pint", 568.0).unwrap() > 0.0);
        assert!(price("Beer", "beer", "can", 440.0).unwrap() > 0.0);
        assert!(price("Red wine", "redWine", "wineGlass", 175.0).unwrap() > 0.0);
        assert_eq!(price("Beer", "beer", "wineGlass", 175.0), None);
        assert_eq!(price("Not a drink", "beer", "pint", 568.0), None);
    }

    #[test]
    fn an_unlisted_size_scales_from_the_nearest_serve_of_the_same_vessel() {
        let bottle = |ml| catalog_brand_price("Asahi Super Dry".into(), CategoryKind::Beer, VesselKind::Bottle, ml, "GBP".into());
        assert!((bottle(660.0) - bottle(330.0) * 2.0).abs() < 1e-9);
        assert!(bottle(440.0) > bottle(330.0) && bottle(440.0) < bottle(660.0));
        let pint = catalog_brand_price("Asahi Super Dry".into(), CategoryKind::Beer, VesselKind::Pint, 568.0, "GBP".into());
        assert!(pint > bottle(330.0));
        assert!(catalog_brand_price("Asahi Super Dry".into(), CategoryKind::Beer, VesselKind::Can, 440.0, "GBP".into()) > 0.0);
    }

    #[test]
    fn another_currency_converts_and_an_unknown_one_prices_at_nothing() {
        let in_ = |currency: &str| catalog_brand_price("Asahi Super Dry".into(), CategoryKind::Beer, VesselKind::Pint, 568.0, currency.into());
        assert!((in_("EUR") - in_("GBP") * 1.16218).abs() < 1e-9);
        assert_eq!(in_("XXX"), 0.0);
        assert_eq!(catalog_brand_price("Nope".into(), CategoryKind::Beer, VesselKind::Pint, 568.0, "GBP".into()), 0.0);
    }

    #[test]
    fn the_generics_cover_every_kind_the_log_grid_starts_with() {
        let generics = catalog_generics();
        assert_eq!(generics.len(), 11);
        let ids: std::collections::HashSet<&String> = generics.iter().map(|g| &g.id).collect();
        assert_eq!(ids.len(), 11);
        assert!(!ids.contains(&catalog_units_id()));
        assert_eq!(generics[0].id, "67726F67-0000-4000-8000-000000000001");
        assert!(generics.iter().all(|g| !g.serves.is_empty() && g.serves.iter().all(|s| s.price > 0.0)));
        assert_eq!(catalog_sizes("Stella Artois".into(), CategoryKind::Beer).len(), 4);
        assert!(catalog_sizes("Nope".into(), CategoryKind::Beer).is_empty());
    }

    #[test]
    fn labels_cover_every_kind() {
        let labels = catalog_category_labels();
        assert_eq!(labels.len(), 12);
        assert!(labels.iter().any(|l| l.category == CategoryKind::RedWine && l.label == "Red wine"));
    }

    /// A drink at £0.00 looks free rather than broken, and silently flattens the spend charts.
    #[test]
    fn every_size_of_every_brand_costs_something() {
        for brand in catalog_brands() {
            for serve in brand.markets.iter().flat_map(|m| &m.serves) {
                assert!(serve.price > 0.0, "{} {:?} {}", brand.name, serve.vessel, serve.ml);
            }
        }
    }

    #[test]
    fn a_price_in_the_markets_own_currency_is_the_listed_one() {
        let asahi = catalog_brands().into_iter().find(|b| b.name == "Asahi Super Dry").unwrap();
        let listed = asahi.markets.iter().find(|m| m.currency == "GBP").unwrap().serves.iter().find(|s| s.vessel == VesselKind::Pint).unwrap().price;
        let pounds = catalog_brand_price(asahi.name.clone(), asahi.category, VesselKind::Pint, 568.0, "GBP".into());
        assert_eq!(pounds, listed);
    }

    /// Lookups go by name and kind, so two brands sharing both would leave one of them unreachable.
    #[test]
    fn no_two_brands_share_a_name_and_kind() {
        let brands = catalog_brands();
        let keys: std::collections::HashSet<_> = brands.iter().map(|b| (b.name.clone(), b.category)).collect();
        assert_eq!(keys.len(), brands.len());
    }

    /// The Swift catalogue as it stood before the table moved here: every brand, the generics, the rates and the
    /// labels, with each answer to a sample of lookups and searches.
    fn golden() -> serde_json::Value {
        serde_json::from_str(include_str!("../tests/catalog_golden.json")).unwrap()
    }

    fn close(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-9
    }

    /// Holds every name, strength, size and price, and the answers to the lookups, to the golden dump, because drinks
    /// logged on a phone refer to them by name and kind.
    #[test]
    fn the_table_matches_the_golden_dump() {
        let golden = golden();
        let brands = catalog_brands();
        let expected = golden["brands"].as_array().unwrap();
        assert_eq!(brands.len(), expected.len());
        for (brand, want) in brands.iter().zip(expected) {
            assert_eq!(brand.name, want["name"].as_str().unwrap());
            assert_eq!(brand.category.raw(), want["category"].as_str().unwrap(), "{}", brand.name);
            assert!(close(brand.abv, want["abv"].as_f64().unwrap()), "{}", brand.name);
            let markets = want["markets"].as_array().unwrap();
            assert_eq!(brand.markets.len(), markets.len(), "{}", brand.name);
            for (market, want) in brand.markets.iter().zip(markets) {
                assert_eq!(market.currency, want["currency"].as_str().unwrap());
                let serves = want["serves"].as_array().unwrap();
                assert_eq!(market.serves.len(), serves.len(), "{}", brand.name);
                for (serve, want) in market.serves.iter().zip(serves) {
                    assert_eq!(serve.vessel.raw(), want["vessel"].as_str().unwrap(), "{}", brand.name);
                    assert!(close(serve.ml, want["ml"].as_f64().unwrap()), "{}", brand.name);
                    assert!(close(serve.price, want["price"].as_f64().unwrap()), "{}", brand.name);
                }
            }
            let sizes = want["sizes"].as_array().unwrap();
            assert_eq!(brand.sizes.len(), sizes.len(), "{}", brand.name);
            for (size, want) in brand.sizes.iter().zip(sizes) {
                assert_eq!(size.vessel.raw(), want["vessel"].as_str().unwrap());
                assert!(close(size.ml, want["ml"].as_f64().unwrap()));
            }
        }
    }

    #[test]
    fn lookups_and_searches_match_the_golden_dump() {
        let golden = golden();
        for lookup in golden["lookups"].as_array().unwrap() {
            let got = catalog_price(
                lookup["name"].as_str().unwrap().into(),
                kind(lookup["category"].as_str().unwrap()),
                vessel(lookup["vessel"].as_str().unwrap()),
                lookup["ml"].as_f64().unwrap(),
                lookup["currency"].as_str().unwrap().into(),
            );
            match lookup["price"].as_f64() {
                Some(want) => assert!(close(got.unwrap_or(f64::NAN), want), "{lookup}"),
                None => assert_eq!(got, None, "{lookup}"),
            }
        }
        let items = catalog_items();
        for search in golden["searches"].as_array().unwrap() {
            let query = search["query"].as_str().unwrap();
            let got: Vec<_> = catalog_search(query.into()).into_iter().map(|i| &items[i as usize]).collect();
            let want = search["items"].as_array().unwrap();
            assert_eq!(got.len(), want.len(), "{query:?}");
            for (item, want) in got.iter().zip(want) {
                let parts: Vec<_> = want.as_str().unwrap().split('|').collect();
                assert_eq!((item.name.as_str(), item.category.raw(), item.vessel.raw()), (parts[0], parts[1], parts[2]), "{query:?}");
                assert_eq!(item.ml as i64, parts[3].parse::<i64>().unwrap());
                assert!(close(item.abv, parts[4].parse().unwrap()));
            }
        }
        for generic in golden["generics"].as_array().unwrap() {
            let name = generic["name"].as_str().unwrap();
            for probe in generic["prices"].as_array().unwrap() {
                let got = generic_price(name, vessel(probe["vessel"].as_str().unwrap()), probe["ml"].as_f64().unwrap());
                match probe["price"].as_f64() {
                    Some(want) => assert!(close(got.unwrap_or(f64::NAN), want), "{name} {probe}"),
                    None => assert_eq!(got, None, "{name} {probe}"),
                }
            }
        }
        let labels: Vec<_> = catalog_category_labels().into_iter().map(|l| (l.category.raw().to_string(), l.label)).collect();
        let want: Vec<_> = golden["labels"]
            .as_array()
            .unwrap()
            .iter()
            .map(|l| (l[0].as_str().unwrap().to_string(), l[1].as_str().unwrap().to_string()))
            .collect();
        for pair in &want {
            assert!(labels.contains(pair), "{pair:?}");
        }
        assert_eq!(labels.len(), want.len());
    }

    #[test]
    fn the_rates_are_the_ones_the_swift_code_held() {
        let golden = golden();
        let rates = &golden["rates"];
        assert_eq!(rates_as_of(), rates["asOf"].as_str().unwrap());
        let currencies: Vec<_> = rates["currencies"].as_array().unwrap().iter().map(|c| c.as_str().unwrap().to_string()).collect();
        assert_eq!(rates_currencies(), currencies);
        let per_pound = rates_per_pound();
        for pair in rates["perPound"].as_array().unwrap() {
            let code = pair[0].as_str().unwrap();
            let rate = per_pound.iter().find(|r| r.currency == code).unwrap();
            assert!(close(rate.per_pound, pair[1].as_f64().unwrap()), "{code}");
        }
        for (code, want) in currencies.iter().zip(rates["converted"].as_array().unwrap()) {
            assert!(close(rates_convert(12.5, "GBP".into(), code.clone()).unwrap(), want.as_f64().unwrap()), "{code}");
        }
        assert_eq!(rates_convert(1.0, "GBP".into(), "XXX".into()), None);
    }
}
