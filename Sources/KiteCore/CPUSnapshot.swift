import Darwin
import Foundation

public struct CPUSnapshot: Equatable, Sendable {
    public let totalPercent: Double
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double
    public let logicalProcessorCount: Int

    public init(totalPercent: Double, userPercent: Double, systemPercent: Double, idlePercent: Double, logicalProcessorCount: Int) {
        self.totalPercent = totalPercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
        self.logicalProcessorCount = logicalProcessorCount
    }
}

public final class MacOSCPUSampler: @unchecked Sendable {
    private var previous: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?

    public init() {}

    public func sample() throws -> CPUSnapshot {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw POSIXError(.EIO)
        }

        let current = (
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
        defer { previous = current }
        guard let previous else {
            return CPUSnapshot(totalPercent: 0, userPercent: 0, systemPercent: 0, idlePercent: 100, logicalProcessorCount: ProcessInfo.processInfo.processorCount)
        }

        let user = delta(current.user, previous.user) + delta(current.nice, previous.nice)
        let system = delta(current.system, previous.system)
        let idle = delta(current.idle, previous.idle)
        let total = user + system + idle
        guard total > 0 else {
            return CPUSnapshot(totalPercent: 0, userPercent: 0, systemPercent: 0, idlePercent: 100, logicalProcessorCount: ProcessInfo.processInfo.processorCount)
        }
        let scale = 100 / Double(total)
        return CPUSnapshot(
            totalPercent: Double(user + system) * scale,
            userPercent: Double(user) * scale,
            systemPercent: Double(system) * scale,
            idlePercent: Double(idle) * scale,
            logicalProcessorCount: ProcessInfo.processInfo.processorCount
        )
    }

    private func delta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }
}
