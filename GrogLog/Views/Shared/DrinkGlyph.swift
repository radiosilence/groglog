import SwiftUI

/// Hand-drawn drink icon. Drawn on a 100×100 canvas so every vessel shares one coordinate space.
struct DrinkGlyph: View {
    let category: DrinkCategory
    let vessel: Vessel
    var volumeMl: Double?
    /// How far poured, 0…1 — animated when a drink is logged.
    var fill = 1.0

    var body: some View {
        if category == .units {
            UnitsBadge()
        } else {
            vesselArt
        }
    }

    private var vesselArt: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 100
            context.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            Art(vessel: vessel, volumeMl: volumeMl ?? vessel.volumes[0]).draw(in: &context, category: category, fill: fill)
        }
        .aspectRatio(1, contentMode: .fit)
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

/// A bare unit count has no vessel, so it gets a counter instead.
private struct UnitsBadge: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Text("u")
                .font(.system(size: side * 0.5, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: side * 0.72, height: side * 0.72)
                .background(Color.grog, in: .circle)
                .overlay(Circle().stroke(.primary, lineWidth: side * 0.035))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct Art {
    /// Outline of the vessel; tinted as glass and stroked.
    var glass: Path
    /// Where liquid can sit, if different from the glass (e.g. above a thick base).
    var bowl: Path?
    /// Fraction of the bowl's height that's filled.
    var level: CGFloat
    /// Stems, feet, caps: filled with ink.
    var solids: [Path] = []
    /// Labels on bottles and cans, drawn over the liquid.
    var label: Path?
    var labelMark: Path?
    var ice = false
    var garnish = false
    let vessel: Vessel

    init(vessel: Vessel, volumeMl: Double) {
        self.vessel = vessel
        switch vessel {
        case .pint:
            glass = Self.nonic(top: 6)
            level = 0.86
        case .half:
            glass = Self.nonic(top: 36)
            level = 0.8
        case .can:
            glass = Path(roundedRect: CGRect(x: 30, y: 12, width: 40, height: 84), cornerRadius: 7)
            level = 1
            solids = [Path(roundedRect: CGRect(x: 43, y: 7, width: 14, height: 4), cornerRadius: 2)]
            label = Path(CGRect(x: 30, y: 42, width: 40, height: 30))
            labelMark = Self.star(center: CGPoint(x: 50, y: 57), radius: 11)
        case .bottle:
            glass = Self.bottle(neck: 44...56, body: 35...65, neckTop: 10, shoulder: 30, bodyTop: 52)
            level = 0.92
            solids = [Path(roundedRect: CGRect(x: 42.5, y: 5, width: 15, height: 6), cornerRadius: 2)]
            label = Path(CGRect(x: 35, y: 60, width: 30, height: 22))
            labelMark = Path(ellipseIn: CGRect(x: 44, y: 65, width: 12, height: 12))
        case .wineBottle:
            glass = Self.bottle(neck: 45...55, body: 33...67, neckTop: 6, shoulder: 28, bodyTop: 46)
            level = 0.9
            solids = [Path(roundedRect: CGRect(x: 44, y: 3, width: 12, height: 16), cornerRadius: 2)]
            label = Path(CGRect(x: 33, y: 60, width: 34, height: 24))
            labelMark = Path(ellipseIn: CGRect(x: 44, y: 66, width: 12, height: 12))
        case .wineGlass:
            var bowl = Path()
            bowl.move(to: CGPoint(x: 27, y: 8))
            bowl.addLine(to: CGPoint(x: 73, y: 8))
            bowl.addCurve(to: CGPoint(x: 50, y: 56), control1: CGPoint(x: 76, y: 32), control2: CGPoint(x: 71, y: 51))
            bowl.addCurve(to: CGPoint(x: 27, y: 8), control1: CGPoint(x: 29, y: 51), control2: CGPoint(x: 24, y: 32))
            bowl.closeSubpath()
            glass = bowl
            level = volumeMl <= 70 ? 0.3 : volumeMl <= 125 ? 0.45 : volumeMl <= 175 ? 0.58 : 0.74
            solids = Self.stem(from: 55, width: 3.6) + [Path(ellipseIn: CGRect(x: 30, y: 88, width: 40, height: 8))]
        case .flute:
            var bowl = Path()
            bowl.move(to: CGPoint(x: 39, y: 6))
            bowl.addLine(to: CGPoint(x: 61, y: 6))
            bowl.addCurve(to: CGPoint(x: 50, y: 62), control1: CGPoint(x: 62, y: 34), control2: CGPoint(x: 60, y: 54))
            bowl.addCurve(to: CGPoint(x: 39, y: 6), control1: CGPoint(x: 40, y: 54), control2: CGPoint(x: 38, y: 34))
            bowl.closeSubpath()
            glass = bowl
            level = 0.82
            solids = Self.stem(from: 61, width: 3) + [Path(ellipseIn: CGRect(x: 35, y: 88, width: 30, height: 7))]
        case .shot:
            glass = Self.tapered(top: 46, left: 34, right: 66, inset: 4)
            bowl = Self.tapered(top: 46, left: 34, right: 66, inset: 4, bottom: 84)
            level = 0.72
        case .tumbler:
            glass = Self.tapered(top: 36, left: 26, right: 74, inset: 3)
            bowl = Self.tapered(top: 36, left: 26, right: 74, inset: 3, bottom: 89)
            level = 0.55
            ice = true
        case .coupe:
            var bowl = Path()
            bowl.move(to: CGPoint(x: 20, y: 14))
            bowl.addLine(to: CGPoint(x: 80, y: 14))
            bowl.addLine(to: CGPoint(x: 52, y: 46))
            bowl.addQuadCurve(to: CGPoint(x: 48, y: 46), control: CGPoint(x: 50, y: 48.5))
            bowl.closeSubpath()
            glass = bowl
            level = 0.8
            solids = Self.stem(from: 46, width: 3) + [Path(ellipseIn: CGRect(x: 33, y: 88, width: 34, height: 7))]
            garnish = true
        }
        if let (full, exponent) = Self.sizing[vessel] {
            scale(by: pow(volumeMl / full, exponent))
        }
    }

    /// Rectangular containers are drawn to size: the largest common serve fills the frame and smaller ones shrink
    /// towards its base, so a 330 can sits visibly shorter than a 568.
    private static let sizing: [Vessel: (full: Double, exponent: Double)] = [
        .can: (568, 0.6),
        .bottle: (660, 0.5),
        .wineBottle: (750, 0.4),
    ]

    private mutating func scale(by factor: Double) {
        let factor = min(1, max(0.5, factor))
        let transform = CGAffineTransform(translationX: 50, y: 96)
            .scaledBy(x: pow(factor, 0.35), y: factor)
            .translatedBy(x: -50, y: -96)
        glass = glass.applying(transform)
        bowl = bowl?.applying(transform)
        solids = solids.map { $0.applying(transform) }
        label = label?.applying(transform)
        labelMark = labelMark?.applying(transform)
    }

    func draw(in context: inout GraphicsContext, category: DrinkCategory, fill: Double) {
        let ink = Color.primary
        let liquidArea = bowl ?? glass
        let bounds = liquidArea.boundingRect
        let full = bounds.maxY - bounds.height * level
        let surface = bounds.maxY - bounds.height * level * max(0, min(1, fill))
        let hasHead = category.hasHead && [.pint, .half].contains(vessel)

        context.fill(glass, with: .color(ink.opacity(0.06)))

        context.drawLayer { layer in
            layer.clip(to: liquidArea)
            layer.fill(Path(CGRect(x: 0, y: surface, width: 100, height: 100)), with: .color(category.liquid))
            if category.isFizzy, label == nil {
                for (x, y, r) in [(0.3, 0.55, 1.6), (0.62, 0.7, 2.0), (0.45, 0.85, 1.4), (0.7, 0.42, 1.3), (0.38, 0.3, 1.1)] {
                    let point = CGPoint(x: bounds.minX + bounds.width * x, y: surface + (bounds.maxY - surface) * y)
                    layer.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.7)))
                }
            }
        }

        var foam: Path?
        if hasHead, fill > 0.05 {
            // The head rides on the liquid as it pours, and crowns over the rim once full.
            let top = surface - (full - bounds.minY)
            let head = Path(CGRect(x: 0, y: top, width: 100, height: surface - top + 1)).intersection(glass)
            var bubbles = Path()
            let count = max(2, Int((bounds.width - 10) / 8.5) + 1)
            for index in 0..<count {
                let x = bounds.minX + 5 + (bounds.width - 10) * CGFloat(index) / CGFloat(count - 1)
                bubbles.addEllipse(in: CGRect(x: x - 5.5, y: top - 4.5, width: 11, height: 10))
            }
            foam = head.union(fill >= 1 ? bubbles : bubbles.intersection(glass))
            context.fill(foam!, with: .color(.white))
        }

        if ice, let bowl {
            let iceBounds = bowl.boundingRect
            for (dx, dy, angle) in [(0.2, 0.2, -12.0), (0.5, 0.26, 10.0)] {
                let rect = CGRect(x: iceBounds.minX + iceBounds.width * dx, y: surface - 6 + iceBounds.height * dy * 0.4, width: 15, height: 15)
                let cube = Path(roundedRect: rect, cornerRadius: 3).applying(
                    CGAffineTransform(translationX: rect.midX, y: rect.midY)
                        .rotated(by: angle * .pi / 180)
                        .translatedBy(x: -rect.midX, y: -rect.midY)
                )
                context.fill(cube, with: .color(.white.opacity(0.55)))
                context.stroke(cube, with: .color(ink.opacity(0.5)), lineWidth: 1.8)
            }
        }

        if let label {
            context.fill(label.intersection(glass), with: .color(.white.opacity(0.92)))
            if let labelMark {
                context.fill(labelMark, with: .color(vessel == .can ? .red : category.liquid))
            }
        }

        let line = StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
        context.stroke(glass, with: .color(ink), style: line)
        if let foam {
            context.stroke(foam, with: .color(ink), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }
        for solid in solids {
            context.fill(solid, with: .color(ink))
        }

        if garnish {
            context.stroke(Path { $0.move(to: CGPoint(x: 66, y: 8)); $0.addLine(to: CGPoint(x: 56, y: 26)) }, with: .color(ink), style: line)
            context.fill(Path(ellipseIn: CGRect(x: 60, y: 6, width: 11, height: 11)), with: .color(Color(red: 0.8, green: 0.1, blue: 0.2)))
        }

        if label == nil, vessel != .can {
            var glint = Path()
            glint.move(to: CGPoint(x: bounds.minX + bounds.width * 0.2, y: bounds.minY + bounds.height * 0.18))
            glint.addLine(to: CGPoint(x: bounds.minX + bounds.width * 0.22, y: bounds.minY + bounds.height * 0.5))
            context.drawLayer { layer in
                layer.clip(to: glass)
                layer.stroke(glint, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }

    // MARK: Shapes

    /// A nonic pint glass with its characteristic bulge near the rim.
    private static func nonic(top: CGFloat) -> Path {
        let height = 96 - top
        let bulge = top + height * 0.27
        var path = Path()
        path.move(to: CGPoint(x: 24, y: top))
        path.addLine(to: CGPoint(x: 76, y: top))
        path.addLine(to: CGPoint(x: 73, y: bulge - 4))
        path.addQuadCurve(to: CGPoint(x: 73, y: bulge + 4), control: CGPoint(x: 76, y: bulge))
        path.addLine(to: CGPoint(x: 67, y: 93))
        path.addQuadCurve(to: CGPoint(x: 63, y: 96), control: CGPoint(x: 66.5, y: 96))
        path.addLine(to: CGPoint(x: 37, y: 96))
        path.addQuadCurve(to: CGPoint(x: 33, y: 93), control: CGPoint(x: 33.5, y: 96))
        path.addLine(to: CGPoint(x: 27, y: bulge + 4))
        path.addQuadCurve(to: CGPoint(x: 27, y: bulge - 4), control: CGPoint(x: 24, y: bulge))
        path.closeSubpath()
        return path
    }

    private static func bottle(neck: ClosedRange<CGFloat>, body: ClosedRange<CGFloat>, neckTop: CGFloat, shoulder: CGFloat, bodyTop: CGFloat) -> Path {
        let mid = (shoulder + bodyTop) / 2
        var path = Path()
        path.move(to: CGPoint(x: neck.lowerBound, y: neckTop))
        path.addLine(to: CGPoint(x: neck.upperBound, y: neckTop))
        path.addLine(to: CGPoint(x: neck.upperBound, y: shoulder))
        path.addCurve(to: CGPoint(x: body.upperBound, y: bodyTop), control1: CGPoint(x: neck.upperBound, y: mid), control2: CGPoint(x: body.upperBound, y: mid))
        path.addLine(to: CGPoint(x: body.upperBound, y: 92))
        path.addQuadCurve(to: CGPoint(x: body.upperBound - 4, y: 96), control: CGPoint(x: body.upperBound, y: 96))
        path.addLine(to: CGPoint(x: body.lowerBound + 4, y: 96))
        path.addQuadCurve(to: CGPoint(x: body.lowerBound, y: 92), control: CGPoint(x: body.lowerBound, y: 96))
        path.addLine(to: CGPoint(x: body.lowerBound, y: bodyTop))
        path.addCurve(to: CGPoint(x: neck.lowerBound, y: shoulder), control1: CGPoint(x: body.lowerBound, y: mid), control2: CGPoint(x: neck.lowerBound, y: mid))
        path.closeSubpath()
        return path
    }

    /// Straight-sided glass narrowing towards the base.
    private static func tapered(top: CGFloat, left: CGFloat, right: CGFloat, inset: CGFloat, bottom: CGFloat = 96) -> Path {
        let t = (bottom - top) / (96 - top)
        var path = Path()
        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: right - inset * t, y: bottom))
        path.addLine(to: CGPoint(x: left + inset * t, y: bottom))
        path.closeSubpath()
        return path
    }

    private static func stem(from top: CGFloat, width: CGFloat) -> [Path] {
        [Path(CGRect(x: 50 - width / 2, y: top, width: width, height: 90 - top))]
    }

    private static func star(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for i in 0..<10 {
            let r = i.isMultiple(of: 2) ? radius : radius * 0.45
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(), count: 5)) {
        ForEach(Vessel.allCases) { vessel in
            DrinkGlyph(category: .beer, vessel: vessel).frame(height: 64)
        }
    }
    .padding()
}
