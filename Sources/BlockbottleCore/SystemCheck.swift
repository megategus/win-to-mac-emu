import Foundation

public struct SystemReport: Equatable, Sendable {
    public var appleSilicon: Bool
    public var macOSOK: Bool
    public var rosetta: Bool
    public var allGood: Bool { appleSilicon && macOSOK && rosetta }

    public init(appleSilicon: Bool, macOSOK: Bool, rosetta: Bool) {
        self.appleSilicon = appleSilicon
        self.macOSOK = macOSOK
        self.rosetta = rosetta
    }
}

public struct SystemCheck: Sendable {
    public static let rosettaProbe = WineInvocation(
        executable: URL(fileURLWithPath: "/usr/bin/arch"), arguments: ["-x86_64", "/usr/bin/true"])
    public static let rosettaInstall = WineInvocation(
        executable: URL(fileURLWithPath: "/usr/sbin/softwareupdate"),
        arguments: ["--install-rosetta", "--agree-to-license"])

    let runner: ProcessRunner
    let machine: @Sendable () -> String
    let osVersion: OperatingSystemVersion

    public init(runner: ProcessRunner,
                machine: @escaping @Sendable () -> String = { SystemCheck.hardwareMachine() },
                osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) {
        self.runner = runner
        self.machine = machine
        self.osVersion = osVersion
    }

    public func report() async -> SystemReport {
        let rosetta = ((try? await runner.run(Self.rosettaProbe, logTo: nil)) ?? 1) == 0
        return SystemReport(appleSilicon: machine().hasPrefix("arm64"),
                            macOSOK: osVersion.majorVersion >= 14,
                            rosetta: rosetta)
    }

    public static func hardwareMachine() -> String {
        var info = utsname()
        uname(&info)
        var machine = info.machine
        let size = MemoryLayout.size(ofValue: machine)
        return withUnsafePointer(to: &machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: size) { String(cString: $0) }
        }
    }
}
