import SwiftUI

struct StoragePickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ShadowText("Where should Blockbottle keep its world?", size: 24)
            ShadowText("Wine, bottles, Steam and every game will live here.", size: 13, color: Color(hex: 0xA0A0A0))

            InventoryPanel {
                Text(model.suggestedRoot.path)
                    .font(.pixel(13))
                    .foregroundStyle(Palette.textDark)
                    .textSelection(.enabled)
                Text("External drives must be formatted APFS or Mac OS Extended.")
                    .font(.pixel(11))
                    .foregroundStyle(Palette.panelDark)
            }
            .frame(maxWidth: 560)

            if let error = model.storageError {
                ShadowText(error, size: 13, color: Color(hex: 0xFF5555))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }

            Button("Use this folder") { model.chooseRoot(model.suggestedRoot) }
                .buttonStyle(.block(.green, minWidth: 400))
            Button("Choose another folder…") { model.pickFolder() }
                .buttonStyle(.block(.stone, minWidth: 400))
            Spacer()
        }
        .padding()
    }
}

struct WorldMissingView: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ShadowText(message, size: 24)
            ShadowText("Blockbottle won't create a new world while your drive is unplugged.",
                       size: 13, color: Color(hex: 0xA0A0A0))
            Button("Try again") { model.retryWorld() }
                .buttonStyle(.block(.green, minWidth: 400))
            Button("Choose another folder…") { model.pickFolder() }
                .buttonStyle(.block(.stone, minWidth: 400))
            Spacer()
        }
    }
}
