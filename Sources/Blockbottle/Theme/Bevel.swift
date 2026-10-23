import SwiftUI

/// The chunky light-top-left / dark-bottom-right border of block UIs.
struct Bevel: ViewModifier {
    var light: Color
    var dark: Color
    var width: CGFloat = 2
    var outline: Color? = .black

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) { light.frame(height: width) }
            .overlay(alignment: .leading) { light.frame(width: width) }
            .overlay(alignment: .bottom) { dark.frame(height: width) }
            .overlay(alignment: .trailing) { dark.frame(width: width) }
            .overlay { if let outline { Rectangle().strokeBorder(outline, lineWidth: 1) } }
    }
}

extension View {
    func bevel(light: Color, dark: Color, width: CGFloat = 2, outline: Color? = .black) -> some View {
        modifier(Bevel(light: light, dark: dark, width: width, outline: outline))
    }
}
