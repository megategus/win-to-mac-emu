import BlockbottleCore
import SwiftUI

struct GameDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let game: SteamGame
    @State private var profile = GameProfile()

    private var installed: Set<GraphicsBackend> { model.wineEnvironment?.installedBackends() ?? [.wined3d] }

    var body: some View {
        InventoryPanel(title: game.name) {
            AsyncImage(url: game.headerImageURL) { image in
                image.resizable().aspectRatio(460 / 215, contentMode: .fit)
            } placeholder: { GameSlot.Placeholder().frame(height: 160) }
            .frame(maxWidth: .infinity)
            .bevel(light: Palette.slotDark, dark: Palette.panelLight)

            if AntiCheatList.isBlocked(game.appID) {
                Text("⚠ This game uses anti-cheat that doesn't run under Wine. It will probably not start.")
                    .font(.pixel(11)).foregroundStyle(Palette.redstone)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    label("DirectX")
                    Picker("", selection: $profile.directX) {
                        ForEach(DirectXVersion.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: profile.directX) { _, dx in profile.backend = GraphicsBackend.recommended(for: dx) }
                }
                GridRow {
                    label("Graphics")
                    VStack(alignment: .leading, spacing: 2) {
                        Picker("", selection: $profile.backend) {
                            ForEach(GraphicsBackend.allCases) { b in
                                Text(installed.contains(b) ? b.displayName : "\(b.displayName) (not installed)").tag(b)
                            }
                        }
                        .labelsHidden()
                        Text(profile.backend.summary).font(.pixel(10)).foregroundStyle(Palette.panelDark)
                    }
                }
                GridRow {
                    label("Display")
                    HStack(spacing: 16) {
                        Toggle("Retina", isOn: $profile.retinaMode)
                        Toggle("Metal HUD", isOn: $profile.metalHUD)
                        Toggle("MSync", isOn: $profile.msync)
                    }
                    .font(.pixel(12))
                    .foregroundStyle(Palette.textDark)
                }
                GridRow {
                    label("Arguments")
                    TextField("-windowed -dx11", text: $profile.launchArguments)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
            }

            HStack {
                Button("Close") { model.save(profile, for: game); dismiss() }
                    .buttonStyle(.block(.stone, minWidth: 110, fontSize: 14))
                Button("Logs") { openLogs() }
                    .buttonStyle(.block(.stone, minWidth: 110, fontSize: 14))
                Spacer()
                if model.isRunning(game) {
                    Button("Stop") { Task { await model.stop(game) } }
                        .buttonStyle(.block(.red, minWidth: 200, fontSize: 18))
                } else {
                    Button("Launch") {
                        model.save(profile, for: game)
                        Task { await model.launch(game) }
                    }
                    .buttonStyle(.block(.green, minWidth: 200, fontSize: 18))
                }
            }
        }
        .frame(width: 620)
        .onAppear { profile = model.profile(for: game) }
        .onChange(of: profile) { _, p in model.save(p, for: game) }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.pixel(12)).foregroundStyle(Palette.textDark).frame(width: 90, alignment: .leading)
    }

    private func openLogs() {
        guard let paths = model.paths, let bottle = model.selectedBottle else { return }
        let dir = paths.logs.appendingPathComponent(bottle.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}
