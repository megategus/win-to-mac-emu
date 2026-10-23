import SwiftUI

struct TitleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack(alignment: .bottomTrailing) {
                Text("BLOCKBOTTLE")
                    .font(.pixel(64))
                    .foregroundStyle(
                        LinearGradient(colors: [Palette.stoneLight, Palette.stone], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black, radius: 0, x: 5, y: 5)
                SplashText(text: model.splash)
                    .offset(x: 70, y: 10)
            }
            .padding(.bottom, 36)

            Button("Play") { model.route = .library }
                .buttonStyle(.block(.stone, minWidth: 400))
            Button("Bottles") { model.route = .bottles }
                .buttonStyle(.block(.stone, minWidth: 400))
            HStack(spacing: 8) {
                Button("Settings…") { model.route = .settings }
                    .buttonStyle(.block(.stone, minWidth: 196))
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.block(.stone, minWidth: 196))
            }
            Spacer()
            HStack {
                ShadowText("Blockbottle 0.1.0", size: 11)
                Spacer()
                ShadowText("Powered by Wine · not affiliated with Mojang or Valve", size: 11)
            }
            .padding(12)
        }
    }
}
