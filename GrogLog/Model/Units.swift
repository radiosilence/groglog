import SwiftUI

nonisolated enum Units {
    /// UK units: 10 ml of pure alcohol.
    static func of(ml: Double, abv: Double) -> Double { ml * abv / 1000 }

    /// Whether a typed strength is one a drink can have: above zero and at most pure alcohol.
    static func isStrength(_ abv: Double) -> Bool { abv > 0 && abv <= 100 }

    /// Ethanol at 0.789 g/ml and 7 kcal/g, plus the category's non-alcohol calories.
    static func kcal(ml: Double, abv: Double, category: DrinkCategory) -> Double {
        ml * abv / 100 * 0.789 * 7 + ml * category.kcalPerMl
    }

    /// UK Chief Medical Officers' low-risk weekly guideline.
    static let weeklyGuideline = 14.0

    static let unitMl = 10.0

    /// Health's standard drink: 14 g of alcohol, which at 0.789 g/ml is 17.7 ml, nearly two UK units.
    static let standardDrinkMl = 14 / 0.789
}

nonisolated enum DrinkCategory: String, CaseIterable, Codable, Identifiable {
    case beer, stout, cider, redWine, whiteWine, rose, bubbles, spirit, alcopop, cocktail, fortified
    /// A bare unit count, for when the drinks themselves were not recorded, such as imports.
    case units

    var id: Self { self }

    var label: String {
        switch self {
        case .beer: "Beer"
        case .stout: "Stout"
        case .cider: "Cider"
        case .redWine: "Red wine"
        case .whiteWine: "White wine"
        case .rose: "Rosé"
        case .bubbles: "Bubbles"
        case .spirit: "Spirits"
        case .alcopop: "Alcopop"
        case .cocktail: "Cocktail"
        case .fortified: "Port & sherry"
        case .units: "Units"
        }
    }

    var liquid: Color {
        switch self {
        case .beer: Color(red: 0.96, green: 0.68, blue: 0.20)
        case .stout: Color(red: 0.16, green: 0.09, blue: 0.06)
        case .cider: Color(red: 0.90, green: 0.76, blue: 0.28)
        case .redWine: Color(red: 0.56, green: 0.08, blue: 0.20)
        case .whiteWine: Color(red: 0.95, green: 0.87, blue: 0.52)
        case .rose: Color(red: 0.97, green: 0.58, blue: 0.62)
        case .bubbles: Color(red: 0.98, green: 0.85, blue: 0.48)
        case .spirit: Color(red: 0.80, green: 0.50, blue: 0.20)
        case .alcopop: Color(red: 0.30, green: 0.70, blue: 0.92)
        case .cocktail: Color(red: 0.93, green: 0.35, blue: 0.55)
        case .fortified: Color(red: 0.42, green: 0.10, blue: 0.16)
        case .units: Color(red: 0.97, green: 0.64, blue: 0.20)
        }
    }

    /// Non-alcohol calories per ml, tuned so common serves land near Drinkaware's reference figures.
    var kcalPerMl: Double {
        switch self {
        case .beer: 0.10
        case .stout: 0.12
        case .cider: 0.13
        case .redWine, .whiteWine: 0.15
        case .rose: 0.18
        case .bubbles: 0.05
        case .spirit, .units: 0
        case .alcopop, .cocktail: 0.40
        case .fortified: 0.50
        }
    }

    var isFizzy: Bool { [.beer, .cider, .bubbles, .alcopop].contains(self) }
    var hasHead: Bool { [.beer, .stout, .cider].contains(self) }

    var defaultVessel: Vessel {
        switch self {
        case .beer, .stout, .cider: .pint
        case .redWine, .whiteWine, .rose, .fortified: .wineGlass
        case .bubbles: .flute
        case .spirit, .units: .shot
        case .alcopop: .bottle
        case .cocktail: .coupe
        }
    }

    /// Drinkaware's standard strengths, used for the generic drinks.
    var defaultABV: Double {
        switch self {
        case .beer, .stout: 4
        case .cider: 4.5
        case .redWine, .whiteWine, .rose, .bubbles: 12
        case .spirit: 40
        case .alcopop: 5
        case .cocktail: 15
        case .fortified: 20
        case .units: 100
        }
    }

    /// The sizes this kind of drink usually comes in.
    var serves: [ServeSize] {
        let sizes: [(Vessel, Double)] = switch self {
        case .beer: [(.pint, 568), (.half, 284), (.can, 330), (.can, 440), (.can, 500), (.can, 568), (.bottle, 330), (.bottle, 500), (.bottle, 660)]
        case .stout: [(.pint, 568), (.half, 284), (.can, 440), (.can, 500)]
        case .cider: [(.pint, 568), (.half, 284), (.can, 440), (.can, 500), (.bottle, 500), (.bottle, 568)]
        case .redWine, .whiteWine, .rose: [(.wineGlass, 125), (.wineGlass, 175), (.wineGlass, 250), (.wineBottle, 750)]
        case .bubbles: [(.flute, 125), (.wineBottle, 750)]
        case .spirit: [(.shot, 25), (.shot, 35), (.wineBottle, 700)]
        case .alcopop: [(.bottle, 275), (.can, 250), (.can, 330)]
        case .cocktail: [(.coupe, 150), (.tumbler, 250)]
        case .fortified: [(.wineGlass, 50), (.wineGlass, 70)]
        case .units: [(.shot, 10)]
        }
        return sizes.map(ServeSize.init)
    }

    /// "Pint · 4.6%" or "440 ml can · 5%", or "any amount" for bare unit counts.
    func serving(_ vessel: Vessel, ml: Double, abv: Double) -> String {
        self == .units ? "any amount" : "\(vessel.label(ml: ml)) · \(abv.formatted(.number.precision(.fractionLength(0...1))))%"
    }
}

/// A vessel at a volume: a size a drink comes in.
nonisolated struct ServeSize: Hashable, Sendable {
    let vessel: Vessel
    let ml: Double

    init(_ vessel: Vessel, _ ml: Double) {
        self.vessel = vessel
        self.ml = ml
    }

    var label: String { vessel.label(ml: ml) }
}

nonisolated enum Vessel: String, CaseIterable, Codable, Identifiable {
    case pint, half, can, bottle, wineBottle, wineGlass, flute, shot, tumbler, coupe

    var id: Self { self }

    /// How a serve reads on a tile: "Pint", "440 ml can", "175 ml glass", "Single".
    func label(ml: Double) -> String {
        let size = "\(Int(ml)) ml"
        return switch self {
        case .pint: "Pint"
        case .half: "Half"
        case .can: "\(size) can"
        case .bottle: "\(size) bottle"
        case .wineBottle: ml >= 700 ? "Bottle" : "\(size) bottle"
        case .wineGlass: "\(size) glass"
        case .flute: "Glass"
        case .shot: ml <= 35 ? "\(size) single" : "\(size) shot"
        case .tumbler: ml == 50 ? "Double" : size
        case .coupe: size
        }
    }

    /// For tight spaces where an icon shows the vessel, so the label gives only the size.
    func shortLabel(ml: Double) -> String {
        switch self {
        case .pint: "Pint"
        case .half: "Half"
        case .flute: "Glass"
        case .wineBottle where ml >= 700: "Bottle"
        case .shot where ml <= 35: "Single"
        case .tumbler where ml == 50: "Double"
        default: "\(Int(ml)) ml"
        }
    }

    var volumes: [Double] {
        switch self {
        case .pint: [568]
        case .half: [284]
        case .can: [330, 440, 500, 568]
        case .bottle: [275, 330, 500, 660]
        case .wineBottle: [750, 375]
        case .wineGlass: [125, 175, 250]
        case .flute: [125]
        case .shot: [25, 35, 50]
        case .tumbler: [25, 50, 200]
        case .coupe: [100, 150, 200]
        }
    }
}
