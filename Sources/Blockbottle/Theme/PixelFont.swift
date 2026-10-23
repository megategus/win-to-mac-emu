import SwiftUI
import CoreText

enum PixelFont {
    static let name = "Monocraft"
    private static var registered = false

    /// Registers the bundled Monocraft font (SIL OFL). Safe to call repeatedly.
    static func register() {
        guard !registered else { return }
        registered = true
        // Copied into Contents/Resources by scripts/build-app.sh.
        if let url = Bundle.main.url(forResource: "Monocraft", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static var isAvailable: Bool {
        NSFont(name: name, size: 12) != nil
    }
}

extension Font {
    static func pixel(_ size: CGFloat) -> Font {
        PixelFont.isAvailable ? .custom(PixelFont.name, size: size) : .system(size: size, design: .monospaced)
    }
}

/// White text with the hard 1-pixel drop shadow block games use.
struct ShadowText: View {
    let text: String
    var size: CGFloat = 16
    var color: Color = Palette.text

    init(_ text: String, size: CGFloat = 16, color: Color = Palette.text) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.pixel(size))
            .foregroundStyle(color)
            .shadow(color: Palette.textShadow, radius: 0, x: size / 8, y: size / 8)
    }
}
