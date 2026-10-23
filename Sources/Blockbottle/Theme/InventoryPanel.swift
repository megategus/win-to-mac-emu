import SwiftUI

/// Light-gray inventory-style panel.
struct InventoryPanel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.pixel(16)).foregroundStyle(Palette.textDark)
            }
            content
        }
        .padding(16)
        .background(Palette.panel)
        .bevel(light: Palette.panelLight, dark: Palette.panelDark, width: 3)
    }
}

/// Dark inset square that holds an item (a game).
struct InventorySlot<Content: View>: View {
    var selected = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Palette.slot)
            .bevel(light: Palette.slotDark, dark: Palette.panelLight, width: 2, outline: selected ? Palette.splashYellow : nil)
    }
}

/// Segmented green progress bar.
struct BlockProgressBar: View {
    var value: Double
    var segments = 20

    var body: some View {
        GeometryReader { geo in
            let filled = Int((min(max(value, 0), 1) * Double(segments)).rounded(.down))
            HStack(spacing: 2) {
                ForEach(0..<segments, id: \.self) { i in
                    Rectangle().fill(i < filled ? Palette.grassLight : Palette.slotDark)
                }
            }
            .padding(3)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color.black)
        }
        .frame(height: 20)
    }
}

/// Yellow tilted, pulsing tagline.
struct SplashText: View {
    let text: String
    @State private var pulse = false

    var body: some View {
        Text(text)
            .font(.pixel(15))
            .foregroundStyle(Palette.splashYellow)
            .shadow(color: Color(hex: 0x3F3F00), radius: 0, x: 2, y: 2)
            .scaleEffect(pulse ? 1.08 : 1.0)
            .rotationEffect(.degrees(-20))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}
