import BlockbottleCore
import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 12)]

    var body: some View {
        VStack(spacing: 16) {
            ScreenHeader(title: "Select Game")
            toolbar
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    steamSlot
                    ForEach(model.games) { game in
                        GameSlot(game: game, selected: model.selectedGame == game, running: model.isRunning(game))
                            .onTapGesture { model.selectedGame = game }
                    }
                }
                .padding(.horizontal, 24)
                if model.games.isEmpty {
                    ShadowText("No games yet — open Steam, sign in and install some!", size: 14)
                        .padding(.top, 24)
                }
            }
        }
        .sheet(item: Binding(get: { model.selectedGame }, set: { model.selectedGame = $0 })) { game in
            GameDetailView(game: game)
                .environment(model)
        }
        .onAppear { model.refreshLibrary() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if model.bottles.compactMap(\.bottle).count > 1 {
                Picker("", selection: Binding(get: { model.selectedBottle?.id }, set: {
                    model.selectedBottleID = $0
                    model.refreshLibrary()
                })) {
                    ForEach(model.bottles.compactMap(\.bottle)) { b in Text(b.name).tag(Optional(b.id)) }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            Spacer()
            Button("Refresh") { model.refreshLibrary() }
                .buttonStyle(.block(.stone, minWidth: 110, fontSize: 13))
            Button(model.running["steam"] != nil ? "Steam running" : "Open Steam") { model.openSteam() }
                .buttonStyle(.block(.green, minWidth: 160, fontSize: 13))
                .disabled(model.running["steam"] != nil)
        }
        .padding(.horizontal, 24)
    }

    private var steamSlot: some View {
        InventorySlot {
            VStack(spacing: 8) {
                Text("+").font(.pixel(40)).foregroundStyle(.white)
                Text("Install games in Steam").font(.pixel(12)).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
        }
        .onTapGesture { model.openSteam() }
    }
}

struct GameSlot: View {
    let game: SteamGame
    let selected: Bool
    let running: Bool

    var body: some View {
        InventorySlot(selected: selected) {
            VStack(spacing: 0) {
                AsyncImage(url: game.headerImageURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().interpolation(.none).aspectRatio(460 / 215, contentMode: .fill)
                    default: Placeholder()
                    }
                }
                .frame(height: 104)
                .clipped()
                HStack {
                    Text(game.name).font(.pixel(12)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    if running { Text("▶").font(.pixel(12)).foregroundStyle(Palette.grassLight) }
                    if AntiCheatList.isBlocked(game.appID) { Text("⚠").font(.pixel(12)).foregroundStyle(Palette.splashYellow) }
                }
                .padding(.horizontal, 8)
                .frame(height: 46)
            }
        }
        .contentShape(Rectangle())
    }

    /// A grass block drawn from rectangles while the artwork loads.
    struct Placeholder: View {
        var body: some View {
            VStack(spacing: 0) {
                Palette.grassGreen.frame(height: 30)
                Palette.dirt[0]
            }
        }
    }
}
