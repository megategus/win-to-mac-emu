import SwiftUI

@main
struct BlockbottleApp: App {
    @State private var model = AppModel()
    @State private var controllers = ControllerMonitor()

    init() { PixelFont.register() }

    var body: some Scene {
        WindowGroup("Blockbottle") {
            RootView()
                .environment(model)
                .environment(controllers)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { model.start() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
