import Foundation

/// Steam app IDs known not to run under Wine on macOS (kernel anti-cheat or
/// launcher lockouts). Shown as a warning, never as a block.
public enum AntiCheatList {
    public static let blocked: Set<String> = [
        "1172470", // Apex Legends
        "578080",  // PUBG: BATTLEGROUNDS
        "359550",  // Tom Clancy's Rainbow Six Siege
        "2357570", // Overwatch 2
        "1938090", // Call of Duty
    ]

    public static func isBlocked(_ appID: String) -> Bool { blocked.contains(appID) }
}
