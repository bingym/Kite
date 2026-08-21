import Foundation
import Darwin

public protocol ProcessController: Sendable {
    func terminate(pid: Int32) throws
    func forceTerminate(pid: Int32) throws
    func pause(pid: Int32) throws
    func resume(pid: Int32) throws
}

public struct MacOSProcessController: ProcessController {
    public init() {}

    public func terminate(pid: Int32) throws { try send(signal: SIGTERM, to: pid) }
    public func forceTerminate(pid: Int32) throws { try send(signal: SIGKILL, to: pid) }
    public func pause(pid: Int32) throws { try send(signal: SIGSTOP, to: pid) }
    public func resume(pid: Int32) throws { try send(signal: SIGCONT, to: pid) }

    private func send(signal: Int32, to pid: Int32) throws {
        guard kill(pid, signal) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EPERM) }
    }
}
