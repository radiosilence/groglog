// Renders the app icon from the in-app pint glyph, so the icon and the drinks share one hand.
// Run via scripts/render-icon.sh.
import AppKit
import SwiftUI

extension Color {
    static let grog = Color(red: 0.97, green: 0.64, blue: 0.20)
}

struct Icon: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.10, blue: 0.06), Color(red: 0.06, green: 0.04, blue: 0.03)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(colors: [Color.grog.opacity(0.45), .clear], center: .init(x: 0.5, y: 0.58), startRadius: 0, endRadius: 520)
            DrinkGlyph(category: .beer, vessel: .pint)
                .frame(width: 720, height: 720)
                .offset(y: 30)
                .shadow(color: .black.opacity(0.5), radius: 30, y: 20)
        }
        .frame(width: 1024, height: 1024)
        .environment(\.colorScheme, .dark)
    }
}

@main
struct RenderIcon {
    @MainActor static func main() throws {
        let renderer = ImageRenderer(content: Icon())
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        // App icons must be opaque: redraw without an alpha channel.
        let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
