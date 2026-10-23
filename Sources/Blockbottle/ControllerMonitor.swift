import GameController
import Observation

@MainActor
@Observable
final class ControllerMonitor {
    struct Info: Identifiable {
        let id: ObjectIdentifier
        let name: String
        let battery: Float?
    }

    var controllers: [Info] = []
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        GCController.startWirelessControllerDiscovery {}
        refresh()
    }

    func refresh() {
        controllers = GCController.controllers().map {
            Info(id: ObjectIdentifier($0),
                 name: $0.vendorName ?? "Controller",
                 battery: $0.battery.map { $0.batteryLevel })
        }
    }
}
