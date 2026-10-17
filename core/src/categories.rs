//! The kinds of drink and the vessels they come in. They cross to the apps as enums, and sit in the backup format and
//! the apps' databases by their stored names (`redWine`, `wineGlass`).

use serde::de::Error as _;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum CategoryKind {
    Beer,
    Stout,
    Cider,
    RedWine,
    WhiteWine,
    Rose,
    Bubbles,
    Spirit,
    Alcopop,
    Cocktail,
    Fortified,
    Units,
}

impl CategoryKind {
    pub(crate) const ALL: [CategoryKind; 12] = [
        CategoryKind::Beer,
        CategoryKind::Stout,
        CategoryKind::Cider,
        CategoryKind::RedWine,
        CategoryKind::WhiteWine,
        CategoryKind::Rose,
        CategoryKind::Bubbles,
        CategoryKind::Spirit,
        CategoryKind::Alcopop,
        CategoryKind::Cocktail,
        CategoryKind::Fortified,
        CategoryKind::Units,
    ];

    pub(crate) fn raw(self) -> &'static str {
        match self {
            CategoryKind::Beer => "beer",
            CategoryKind::Stout => "stout",
            CategoryKind::Cider => "cider",
            CategoryKind::RedWine => "redWine",
            CategoryKind::WhiteWine => "whiteWine",
            CategoryKind::Rose => "rose",
            CategoryKind::Bubbles => "bubbles",
            CategoryKind::Spirit => "spirit",
            CategoryKind::Alcopop => "alcopop",
            CategoryKind::Cocktail => "cocktail",
            CategoryKind::Fortified => "fortified",
            CategoryKind::Units => "units",
        }
    }

    pub(crate) fn parse(raw: &str) -> Option<CategoryKind> {
        CategoryKind::ALL.into_iter().find(|category| category.raw() == raw)
    }

    /// What the apps show for the kind, which search also matches.
    pub(crate) fn label(self) -> &'static str {
        match self {
            CategoryKind::Beer => "Beer",
            CategoryKind::Stout => "Stout",
            CategoryKind::Cider => "Cider",
            CategoryKind::RedWine => "Red wine",
            CategoryKind::WhiteWine => "White wine",
            CategoryKind::Rose => "Rosé",
            CategoryKind::Bubbles => "Bubbles",
            CategoryKind::Spirit => "Spirits",
            CategoryKind::Alcopop => "Alcopop",
            CategoryKind::Cocktail => "Cocktail",
            CategoryKind::Fortified => "Port & sherry",
            CategoryKind::Units => "Units",
        }
    }

    /// Drinkaware's standard strengths, used for the generic drinks and for a drink a file gives no strength for.
    pub(crate) fn default_abv(self) -> f64 {
        match self {
            CategoryKind::Beer | CategoryKind::Stout => 4.0,
            CategoryKind::Cider => 4.5,
            CategoryKind::RedWine | CategoryKind::WhiteWine | CategoryKind::Rose | CategoryKind::Bubbles => 12.0,
            CategoryKind::Spirit => 40.0,
            CategoryKind::Alcopop => 5.0,
            CategoryKind::Cocktail => 15.0,
            CategoryKind::Fortified => 20.0,
            CategoryKind::Units => 100.0,
        }
    }

    pub(crate) fn default_vessel(self) -> VesselKind {
        match self {
            CategoryKind::Beer | CategoryKind::Stout | CategoryKind::Cider => VesselKind::Pint,
            CategoryKind::RedWine | CategoryKind::WhiteWine | CategoryKind::Rose | CategoryKind::Fortified => VesselKind::WineGlass,
            CategoryKind::Bubbles => VesselKind::Flute,
            CategoryKind::Alcopop => VesselKind::Bottle,
            CategoryKind::Cocktail => VesselKind::Coupe,
            CategoryKind::Spirit | CategoryKind::Units => VesselKind::Shot,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum VesselKind {
    Pint,
    Half,
    Can,
    Bottle,
    WineBottle,
    WineGlass,
    Flute,
    Shot,
    Tumbler,
    Coupe,
}

impl VesselKind {
    pub(crate) const ALL: [VesselKind; 10] = [
        VesselKind::Pint,
        VesselKind::Half,
        VesselKind::Can,
        VesselKind::Bottle,
        VesselKind::WineBottle,
        VesselKind::WineGlass,
        VesselKind::Flute,
        VesselKind::Shot,
        VesselKind::Tumbler,
        VesselKind::Coupe,
    ];

    pub(crate) fn raw(self) -> &'static str {
        match self {
            VesselKind::Pint => "pint",
            VesselKind::Half => "half",
            VesselKind::Can => "can",
            VesselKind::Bottle => "bottle",
            VesselKind::WineBottle => "wineBottle",
            VesselKind::WineGlass => "wineGlass",
            VesselKind::Flute => "flute",
            VesselKind::Shot => "shot",
            VesselKind::Tumbler => "tumbler",
            VesselKind::Coupe => "coupe",
        }
    }

    pub(crate) fn parse(raw: &str) -> Option<VesselKind> {
        VesselKind::ALL.into_iter().find(|vessel| vessel.raw() == raw)
    }
}

macro_rules! by_stored_name {
    ($kind:ident, $what:literal) => {
        impl Serialize for $kind {
            fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
                serializer.serialize_str(self.raw())
            }
        }

        impl<'de> Deserialize<'de> for $kind {
            fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
                let text = String::deserialize(deserializer)?;
                $kind::parse(&text).ok_or_else(|| D::Error::custom(format!(concat!("unknown ", $what, " {}"), text)))
            }
        }
    };
}

by_stored_name!(CategoryKind, "category");
by_stored_name!(VesselKind, "vessel");

/// The strength a drink of this kind starts at. The apps hold their own copy for screens and previews, checked against
/// this one.
#[uniffi::export]
pub fn category_default_abv(category: CategoryKind) -> f64 {
    category.default_abv()
}

/// The vessel a drink of this kind starts in, held by the apps the same way.
#[uniffi::export]
pub fn category_default_vessel(category: CategoryKind) -> VesselKind {
    category.default_vessel()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_kind_has_a_strength_and_a_vessel_and_names_round_trip() {
        for category in CategoryKind::ALL {
            assert!(category.default_abv() > 0.0, "{category:?}");
            assert_eq!(CategoryKind::parse(category.raw()), Some(category));
        }
        for vessel in VesselKind::ALL {
            assert_eq!(VesselKind::parse(vessel.raw()), Some(vessel));
        }
        assert_eq!((CategoryKind::RedWine.default_vessel(), CategoryKind::Fortified.default_abv()), (VesselKind::WineGlass, 20.0));
        assert_eq!((CategoryKind::Units.default_vessel(), CategoryKind::Units.default_abv()), (VesselKind::Shot, 100.0));
    }

    #[test]
    fn stored_names_are_what_serde_reads_and_writes() {
        assert_eq!(serde_json::to_string(&CategoryKind::RedWine).unwrap(), r#""redWine""#);
        assert_eq!(serde_json::from_str::<VesselKind>(r#""wineGlass""#).unwrap(), VesselKind::WineGlass);
        assert!(serde_json::from_str::<CategoryKind>(r#""mead""#).is_err());
    }
}
