// Renders the link-preview image for groglog.io: 1200×630, the size link previews expect, from the app icon and the
// site's own screenshots, so the preview never shows an app that isn't the current one.
// Run via scripts/render-share-image.sh.
import AppKit
import SwiftUI

extension Color {
    static let grog = Color(red: 0.97, green: 0.64, blue: 0.20)
    static let dry = Color(red: 0.20, green: 0.74, blue: 0.60)
}

struct Phone: View {
    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 250)
            .clipShape(.rect(cornerRadius: 34))
            .overlay(RoundedRectangle(cornerRadius: 34).stroke(.white.opacity(0.18), lineWidth: 2))
            .shadow(color: .black.opacity(0.55), radius: 28, y: 18)
    }
}

struct Share: View {
    let icon: NSImage
    let screens: [NSImage]

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.10, blue: 0.06), Color(red: 0.06, green: 0.04, blue: 0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(colors: [Color.grog.opacity(0.35), .clear], center: .init(x: 0.78, y: 0.55), startRadius: 0, endRadius: 520)

            VStack(alignment: .leading, spacing: 0) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 120, height: 120)
                    .clipShape(.rect(cornerRadius: 28))
                    .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                Text("GrogLog")
                    .font(.system(size: 92, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 28)
                Text("A drink diary for cutting down.")
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.top, 4)
                HStack(spacing: 12) {
                    ForEach(["Free", "Private", "Offline"], id: \.self) { word in
                        Text(word)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.09))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                            .background(word == "Private" ? Color.dry : Color.grog, in: .capsule)
                    }
                }
                .padding(.top, 34)
            }
            .padding(.leading, 76)

            HStack(alignment: .top, spacing: 26) {
                Phone(image: screens[0]).rotationEffect(.degrees(-6)).offset(y: 70)
                Phone(image: screens[1]).rotationEffect(.degrees(5)).offset(y: 20)
            }
            .offset(x: 630, y: 120)
        }
        .frame(width: 1200, height: 630)
        .clipped()
        .environment(\.colorScheme, .dark)
    }
}

@main
struct RenderShare {
    @MainActor static func main() throws {
        let load = { (path: String) throws -> NSImage in
            guard let image = NSImage(contentsOfFile: path) else { throw CocoaError(.fileReadNoSuchFile) }
            return image
        }
        let share = Share(
            icon: try load("GrogLog/Assets.xcassets/AppIcon.appiconset/AppIcon.png"),
            screens: [try load("site/public/screens/2-day-light.png"), try load("site/public/screens/3-reports-light.png")]
        )
        let renderer = ImageRenderer(content: share)
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
