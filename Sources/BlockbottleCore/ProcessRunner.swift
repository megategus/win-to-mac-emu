import Foundation

public protocol RunningProcess: AnyObject, Sendable {
    var isRunning: Bool { get }
    func terminate()
    func waitForExit() async -> Int32
}

public protocol ProcessRunner: Sendable {
    /// Runs to completion and returns the exit status.
    func run(_ invocation: WineInvocation, logTo: URL?) async throws -> Int32
    /// Starts and returns immediately.
    func start(_ invocation: WineInvocation, logTo: URL?) throws -> RunningProcess
}

final class SystemRunningProcess: RunningProcess, @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var status: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []

    init(process: Process) {
        self.process = process
        process.terminationHandler = { [weak self] p in self?.finish(p.terminationStatus) }
    }

    private func finish(_ code: Int32) {
        lock.lock()
        status = code
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume(returning: code) }
    }

    var isRunning: Bool { process.isRunning }

    func terminate() { if process.isRunning { process.terminate() } }

    func waitForExit() async -> Int32 {
        await withCheckedContinuation { cont in
            lock.lock()
            if let status {
                lock.unlock()
                cont.resume(returning: status)
            } else {
                waiters.append(cont)
                lock.unlock()
            }
        }
    }
}

/// Real implementation over Foundation `Process`.
public final class SystemProcessRunner: ProcessRunner, @unchecked Sendable {
    public init() {}

    public func start(_ invocation: WineInvocation, logTo: URL?) throws -> RunningProcess {
        let process = Process()
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        if let cwd = invocation.workingDirectory { process.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        env.merge(invocation.environment) { _, new in new }
        process.environment = env
        if let logTo {
            try FileManager.default.createDirectory(at: logTo.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logTo.path) {
                FileManager.default.createFile(atPath: logTo.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logTo)
            handle.seekToEndOfFile()
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }
        let running = SystemRunningProcess(process: process)
        try process.run()
        return running
    }

    public func run(_ invocation: WineInvocation, logTo: URL?) async throws -> Int32 {
        let p = try start(invocation, logTo: logTo)
        return await p.waitForExit()
    }
}

public enum LogTail {
    public static func lastLines(_ n: Int, of url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        var lines = text.components(separatedBy: .newlines)
        if lines.last == "" { lines.removeLast() }
        return lines.suffix(n).joined(separator: "\n")
    }
}
