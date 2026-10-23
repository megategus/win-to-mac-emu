import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            DirtBackground()
            Group {
                switch model.route {
                case .storage: StoragePickerView()
                case .worldMissing(let message): WorldMissingView(message: message)
                case .title: TitleView()
                case .setup: SetupView()
                case .library: LibraryView()
                case .bottles: BottlesView()
                case .settings: SettingsView()
                }
            }
            .transition(.opacity)

            if let toast = model.toast {
                VStack {
                    Spacer()
                    ShadowText(toast, size: 14)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.black.opacity(0.75))
                        .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.route)
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .sheet(item: Binding(get: { model.launchFailure }, set: { model.launchFailure = $0 })) { failure in
            LaunchFailureView(failure: failure)
        }
    }
}

/// Shared top bar with a Back button for sub-screens.
struct ScreenHeader: View {
    @Environment(AppModel.self) private var model
    let title: String
    var back: Route = .title

    var body: some View {
        HStack {
            Button("< Back") { model.route = back }
                .buttonStyle(.block(.stone, minWidth: 100, fontSize: 14))
            Spacer()
            ShadowText(title, size: 24)
            Spacer()
            Color.clear.frame(width: 100, height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }
}

struct LaunchFailureView: View {
    @Environment(\.dismiss) private var dismiss
    let failure: LaunchFailure

    var body: some View {
        InventoryPanel(title: failure.title) {
            Text("Last 50 lines of the Wine log:")
                .font(.pixel(12)).foregroundStyle(Palette.textDark)
            ScrollView {
                Text(failure.log.isEmpty ? "(log is empty)" : failure.log)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(height: 300)
            .background(Color.black)
            HStack {
                Button("Copy log") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(failure.log, forType: .string)
                }
                .buttonStyle(.block(.stone, minWidth: 120, fontSize: 13))
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([failure.logURL]) }
                    .buttonStyle(.block(.stone, minWidth: 140, fontSize: 13))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.block(.green, minWidth: 100, fontSize: 13))
            }
        }
        .frame(width: 640)
    }
}
