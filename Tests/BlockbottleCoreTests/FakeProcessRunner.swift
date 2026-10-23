import Foundation
@testable import BlockbottleCore

final class FakeRunningProcess: RunningProcess, @unchecked Sendable {
    let code: Int32
    init(code: Int32) { self.code = code }
    var isRunning: Bool { false }
    func terminate() {}
    func waitForExit() async -> Int32 { code }
}

final class FakeProcessRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var invocations: [WineInvocation] = []
    var exitCode: (WineInvocation) -> Int32 = { _ in 0 }
    var onRun: (WineInvocation) -> Void = { _ in }

    private func record(_ inv: WineInvocation) {
        lock.lock(); invocations.append(inv); lock.unlock()
        onRun(inv)
    }

    func run(_ invocation: WineInvocation, logTo: URL?) async throws -> Int32 {
        record(invocation)
        return exitCode(invocation)
    }

    func start(_ invocation: WineInvocation, logTo: URL?) throws -> RunningProcess {
        record(invocation)
        return FakeRunningProcess(code: exitCode(invocation))
    }
}
