import BlockbottleCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(ControllerMonitor.self) private var controllers

    var body: some View {
        VStack(spacing: 16) {
            ScreenHeader(title: "Settings")
            ScrollView {
                VStack(spacing: 16) {
                    InventoryPanel(title: "World location") {
                        Text(model.paths?.root.path ?? "—")
                            .font(.pixel(12)).foregroundStyle(Palette.textDark).textSelection(.enabled)
                        HStack {
                            Button("Change…") { model.pickFolder() }
                                .buttonStyle(.block(.stone, minWidth: 130, fontSize: 12))
                            Button("Show in Finder") { if let p = model.paths { NSWorkspace.shared.open(p.root) } }
                                .buttonStyle(.block(.stone, minWidth: 170, fontSize: 12))
                            Button("Logs") { if let p = model.paths { NSWorkspace.shared.open(p.logs) } }
                                .buttonStyle(.block(.stone, minWidth: 90, fontSize: 12))
                        }
                    }

                    InventoryPanel(title: "Engines") {
                        ForEach(EngineManifest.default) { component in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(component.displayName).font(.pixel(12)).foregroundStyle(Palette.textDark)
                                    Text(model.engineManager?.installedVersion(component) ?? "Not installed")
                                        .font(.pixel(10)).foregroundStyle(Palette.panelDark)
                                }
                                Spacer()
                                Button(model.engineManager?.isInstalled(component) == true ? "Update" : "Install") {
                                    Task { await model.reinstall(component) }
                                }
                                .buttonStyle(.block(.stone, minWidth: 110, fontSize: 11))
                            }
                        }
                    }

                    InventoryPanel(title: "Controllers") {
                        if controllers.controllers.isEmpty {
                            Text("No controllers connected. Pair one in System Settings → Bluetooth.")
                                .font(.pixel(11)).foregroundStyle(Palette.panelDark)
                        }
                        ForEach(controllers.controllers) { c in
                            HStack {
                                Text("🎮 \(c.name)").font(.pixel(12)).foregroundStyle(Palette.textDark)
                                Spacer()
                                if let battery = c.battery {
                                    Text("\(Int(battery * 100))%").font(.pixel(11)).foregroundStyle(Palette.panelDark)
                                }
                            }
                        }
                        Text("Wine passes controllers to games through SDL; most Xbox and PlayStation pads work.")
                            .font(.pixel(10)).foregroundStyle(Palette.panelDark)
                    }
                }
                .frame(width: 720)
            }
        }
    }
}
