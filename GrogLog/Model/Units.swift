import SwiftUI

nonisolated enum Units {
    /// UK units: 10 ml of pure alcohol.
    static func of(ml: Double, abv: Double) -> Double { ml * abv / 1000 }

    /// Ethanol at 0.789 g/ml and 7 kcal/g, plus the category's non-alcohol calories.
    static func kcal(ml: Double, abv: Double, category: DrinkCategory) -> Double {
        ml * abv / 100 * 0.789 * 7 + ml * category.kcalPerMl
    }

    /// UK Chief Medical Officers' low-risk weekly guideline.
    static let weeklyGuideline = 14.0
}

nonisolated enum DrinkCategory: String, CaseIterable, Codable, Identifiable {
    case beer, stout, cider, redWine, whiteWine, rose, bubbles, spirit, alcopop, cocktail, fortified
    /// A bare unit count, for when the drinks themselves weren't recorded (imports, catching up).
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

    var defaultABV: Double {
        switch self {
        case .beer, .cider: 4.5
        case .stout: 4.2
        case .redWine: 13.5
        case .whiteWine: 12.5
        case .rose, .bubbles: 12
        case .spirit: 40
        case .alcopop: 4
        case .cocktail: 15
        case .fortified: 20
        case .units: 100
        }
    }

    /// "568 ml · 4.6%", or just "units" for bare unit counts.
    func serving(ml: Double, abv: Double) -> String {
        self == .units ? "units" : "\(Int(ml)) ml · \(abv.formatted(.number.precision(.fractionLength(0...1))))%"
    }
}

nonisolated enum Vessel: String, CaseIterable, Codable, Identifiable {
    case pint, half, can, bottle, wineBottle, wineGlass, flute, shot, tumbler, coupe

    var id: Self { self }

    var label: String {
        switch self {
        case .pint: "Pint"
        case .half: "Half"
        case .can: "Can"
        case .bottle: "Bottle"
        case .wineBottle: "Wine bottle"
        case .wineGlass: "Wine glass"
        case .flute: "Flute"
        case .shot: "Shot"
        case .tumbler: "Tumbler"
        case .coupe: "Cocktail"
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
