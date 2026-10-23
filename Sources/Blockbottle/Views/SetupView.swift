import SwiftUI

struct SetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ShadowText(model.isSettingUp ? "Building terrain…" : "Let's build your world", size: 28)

            InventoryPanel {
                ForEach(model.setupSteps) { step in
                    HStack(alignment: .top, spacing: 10) {
                        icon(for: step.state)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(.pixel(13)).foregroundStyle(Palette.textDark)
                            if let detail = detail(for: step.state) {
                                Text(detail).font(.pixel(10)).foregroundStyle(Palette.panelDark)
                            }
                        }
                        Spacer()
                    }
                }
                BlockProgressBar(value: model.setupProgress)
            }
            .frame(width: 560)

            if model.systemReport?.rosetta == false {
                Button("Install Rosetta 2") { Task { await model.installRosetta() } }
                    .buttonStyle(.block(.green, minWidth: 400))
            }

            Button(hasFailure ? "Try again" : "Start") { Task { await model.runSetup() } }
                .buttonStyle(.block(.green, minWidth: 400))
                .disabled(model.isSettingUp)

            Text("Downloads about 1 GB into \(model.paths?.root.path ?? "your chosen folder").")
                .font(.pixel(11))
                .foregroundStyle(Color(hex: 0xA0A0A0))
            Spacer()
        }
        .onAppear { model.prepareSetupSteps() }
    }

    private var hasFailure: Bool {
        model.setupSteps.contains { if case .failed = $0.state { return true } else { return false } }
    }

    @ViewBuilder
    private func icon(for state: SetupStep.State) -> some View {
        switch state {
        case .pending: Text("·").font(.pixel(14)).foregroundStyle(Palette.panelDark)
        case .running: ProgressView().controlSize(.small)
        case .done: Text("✔").font(.pixel(14)).foregroundStyle(Palette.grassGreen)
        case .failed: Text("✖").font(.pixel(14)).foregroundStyle(Palette.redstone)
        case .skipped: Text("!").font(.pixel(14)).foregroundStyle(Color(hex: 0xB08000))
        }
    }

    private func detail(for state: SetupStep.State) -> String? {
        switch state {
        case .running(let p) where p > 0: return "\(Int(p * 100))%"
        case .failed(let why): return why
        case .skipped(let why): return "Skipped (\(why)) — you can retry in Settings"
        default: return nil
        }
    }
}
