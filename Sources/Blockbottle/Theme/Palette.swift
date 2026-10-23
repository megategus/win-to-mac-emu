import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Block-game palette. All colors are original approximations, no game assets.
enum Palette {
    static let stone = Color(hex: 0x7F7F7F)
    static let stoneLight = Color(hex: 0xBEBEBE)
    static let stoneDark = Color(hex: 0x3F3F3F)
    static let stoneHover = Color(hex: 0x8C96C8)
    static let panel = Color(hex: 0xC6C6C6)
    static let panelLight = Color(hex: 0xFFFFFF)
    static let panelDark = Color(hex: 0x555555)
    static let slot = Color(hex: 0x8B8B8B)
    static let slotDark = Color(hex: 0x373737)
    static let grassGreen = Color(hex: 0x5B8731)
    static let grassLight = Color(hex: 0x7FB238)
    static let redstone = Color(hex: 0xAA2222)
    static let text = Color.white
    static let textDark = Color(hex: 0x3F3F3F)
    static let textShadow = Color(hex: 0x3F3F3F)
    static let splashYellow = Color(hex: 0xFFFF55)
    static let dirt: [Color] = [0x79553A, 0x593D29, 0x966C4A, 0x6C4A32].map(Color.init(hex:))
}
