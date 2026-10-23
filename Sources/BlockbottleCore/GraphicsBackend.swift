import Foundation

public enum DirectXVersion: String, Codable, CaseIterable, Sendable {
    case dx9, dx10, dx11, dx12, unknown

    public var displayName: String {
        switch self {
        case .dx9: return "DirectX 9"
        case .dx10: return "DirectX 10"
        case .dx11: return "DirectX 11"
        case .dx12: return "DirectX 12"
        case .unknown: return "Unknown"
        }
    }
}

public enum GraphicsBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case d3dmetal, dxmt, dxvk, wined3d

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .d3dmetal: return "D3DMetal (Apple GPTK)"
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK + MoltenVK"
        case .wined3d: return "Wine default"
        }
    }

    public var summary: String {
        switch self {
        case .d3dmetal: return "Best for DirectX 11/12 games."
        case .dxmt: return "Native Metal DirectX 10/11. Fast and lightweight."
        case .dxvk: return "Good for DirectX 9–11 through Vulkan."
        case .wined3d: return "Whatever the Wine build ships with. Always available."
        }
    }

    /// DLLs this backend provides as Wine builtins (forced with `=b`).
    public var dllOverrides: [String] {
        switch self {
        case .dxmt: return ["d3d11", "d3d10core", "dxgi", "winemetal"]
        case .dxvk: return ["d3d9", "d3d10core", "d3d11", "dxgi"]
        case .d3dmetal, .wined3d: return []
        }
    }

    /// Folder under `Engines/` whose presence means the backend is installed.
    public var engineDirectory: String? {
        switch self {
        case .d3dmetal: return nil // ships inside the Wine engine
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        case .wined3d: return nil
        }
    }

    public static func recommended(for dx: DirectXVersion) -> GraphicsBackend {
        switch dx {
        case .dx12, .unknown: return .d3dmetal
        case .dx11, .dx10: return .dxmt
        case .dx9: return .dxvk
        }
    }
}
