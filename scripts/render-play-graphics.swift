// Renders Google Play's store graphics from the in-app pint glyph, on the iOS icon's background, so the two stores
// show the same mark. Play applies its own corner mask to the icon, so it is drawn full-bleed.
// Run via scripts/render-play-graphics.sh.
import AppKit
import SwiftUI

extension Color {
    static let grog = Color(red: 0.97, green: 0.64, blue: 0.20)
}

struct Background: View {
    var glow: UnitPoint
    var radius: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.10, blue: 0.06), Color(red: 0.06, green: 0.04, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(colors: [Color.grog.opacity(0.45), .clear], center: glow, startRadius: 0, endRadius: radius)
        }
    }
}

struct Icon: View {
    var body: some View {
        ZStack {
            Background(glow: .init(x: 0.5, y: 0.58), radius: 260)
            DrinkGlyph(category: .beer, vessel: .pint)
                .frame(width: 360, height: 360)
                .offset(y: 15)
                .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
        }
        .frame(width: 512, height: 512)
        .environment(\.colorScheme, .dark)
    }
}

// Play may crop the edges and lay a play button over the middle, so the text keeps to the left and the glyph clear
// of the centre.
struct Feature: View {
    var body: some View {
        ZStack(alignment: .leading) {
            Background(glow: .init(x: 0.8, y: 0.6), radius: 420)
            VStack(alignment: .leading, spacing: 0) {
                Text("GrogLog")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("A drink diary for cutting down.")
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 4)
            }
            .padding(.leading, 80)
            DrinkGlyph(category: .beer, vessel: .pint)
                .frame(width: 380, height: 380)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 14)
                .offset(x: 660, y: 20)
        }
        .frame(width: 1024, height: 500)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

// Play wants both opaque: redraw without an alpha channel.
@MainActor func write(_ view: some View, width: Int, height: Int, to path: String) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    try png.write(to: URL(fileURLWithPath: path))
}

@main
struct RenderPlayGraphics {
    @MainActor static func main() throws {
        let dir = CommandLine.arguments[1]
        try write(Icon(), width: 512, height: 512, to: "\(dir)/icon.png")
        try write(Feature(), width: 1024, height: 500, to: "\(dir)/feature-graphic.png")
    }
}
