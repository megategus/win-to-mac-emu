import BlockbottleCore
import SwiftUI

struct BottlesView: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    @State private var creating = false
    @State private var pendingDelete: BottleEntry?

    var body: some View {
        VStack(spacing: 16) {
            ScreenHeader(title: "Bottles")
            InventoryPanel(title: "Your worlds") {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.bottles) { entry in row(entry) }
                        if model.bottles.isEmpty {
                            Text("No bottles yet.").font(.pixel(12)).foregroundStyle(Palette.textDark)
                        }
                    }
                }
                .frame(maxHeight: 340)

                HStack {
                    TextField("New bottle name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .font(.pixel(12))
                    Button(creating ? "Building…" : "Create") {
                        creating = true
                        Task {
                            await model.createBottle(named: newName)
                            newName = ""
                            creating = false
                        }
                    }
                    .buttonStyle(.block(.green, minWidth: 130, fontSize: 13))
                    .disabled(creating)
                }
            }
            .frame(width: 720)

            HStack(spacing: 8) {
                Button("Wine settings") { model.runTool(["winecfg"]) }
                    .buttonStyle(.block(.stone, minWidth: 180, fontSize: 13))
                Button("Stop all Wine") { Task { await model.killWine() } }
                    .buttonStyle(.block(.red, minWidth: 180, fontSize: 13))
            }
            Spacer()
        }
        .alert("Delete this bottle?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let entry = pendingDelete { model.deleteBottle(entry) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Every game installed in it will be deleted too.")
        }
    }

    @ViewBuilder
    private func row(_ entry: BottleEntry) -> some View {
        HStack(spacing: 10) {
            switch entry {
            case .ok(let bottle):
                Text(bottle.id == model.selectedBottle?.id ? "▶" : " ")
                    .font(.pixel(12)).foregroundStyle(Palette.grassGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bottle.name).font(.pixel(13)).foregroundStyle(Palette.textDark)
                    Text(model.steamInstaller?.isInstalled(bottle: bottle) == true ? "Steam installed" : "No Steam")
                        .font(.pixel(10)).foregroundStyle(Palette.panelDark)
                }
                Spacer()
                Button("Use") { model.selectedBottleID = bottle.id; model.refreshLibrary() }
                    .buttonStyle(.block(.stone, minWidth: 70, fontSize: 11))
                Button("Finder") { NSWorkspace.shared.open(bottle.prefix) }
                    .buttonStyle(.block(.stone, minWidth: 80, fontSize: 11))
            case .damaged(let url):
                Text("✖").font(.pixel(12)).foregroundStyle(Palette.redstone)
                Text("Damaged: \(url.lastPathComponent)").font(.pixel(12)).foregroundStyle(Palette.redstone)
                Spacer()
            }
            Button("Delete") { pendingDelete = entry }
                .buttonStyle(.block(.red, minWidth: 80, fontSize: 11))
        }
        .padding(8)
        .background(Palette.slot.opacity(0.35))
    }
}
