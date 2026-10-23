import SwiftUI

struct BlockButtonStyle: ButtonStyle {
    enum Kind { case stone, green, red }
    var kind: Kind = .stone
    var minWidth: CGFloat = 200
    var fontSize: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        BlockButtonBody(configuration: configuration, kind: kind, minWidth: minWidth, fontSize: fontSize)
    }
}

private struct BlockButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: BlockButtonStyle.Kind
    let minWidth: CGFloat
    let fontSize: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var fill: Color {
        guard isEnabled else { return Palette.stoneDark }
        switch kind {
        case .stone: return hovering ? Palette.stoneHover : Palette.stone
        case .green: return hovering ? Palette.grassLight : Palette.grassGreen
        case .red: return hovering ? Color(hex: 0xCC3333) : Palette.redstone
        }
    }

    var body: some View {
        configuration.label
            .font(.pixel(fontSize))
            .foregroundStyle(isEnabled ? (hovering ? Palette.splashYellow : Palette.text) : Color(hex: 0xA0A0A0))
            .shadow(color: Palette.textShadow, radius: 0, x: 2, y: 2)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minWidth: minWidth)
            .background(fill)
            .bevel(light: configuration.isPressed ? Palette.stoneDark : Palette.stoneLight.opacity(0.8),
                   dark: configuration.isPressed ? Palette.stoneLight.opacity(0.8) : Palette.stoneDark)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == BlockButtonStyle {
    static var block: BlockButtonStyle { BlockButtonStyle() }
    static func block(_ kind: BlockButtonStyle.Kind, minWidth: CGFloat = 200, fontSize: CGFloat = 16) -> BlockButtonStyle {
        BlockButtonStyle(kind: kind, minWidth: minWidth, fontSize: fontSize)
    }
}
