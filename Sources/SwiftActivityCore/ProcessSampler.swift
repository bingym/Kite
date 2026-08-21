import Foundation

public final class ProcessSampler: @unchecked Sendable {
    private let provider: any ProcessProvider
    private var previousCPU: [Int32: (time: UInt64, date: Date)] = [:]

    public init(provider: any ProcessProvider = MacOSProcessProvider()) {
        self.provider = provider
    }

    public func sample() throws -> [ProcessSnapshot] {
        let now = Date()
        let processes = try provider.snapshot()
        var currentCPU: [Int32: (time: UInt64, date: Date)] = [:]

        let sampled = processes.map { process in
            let cpuTime = process.cpuTimeNanoseconds
            currentCPU[process.id] = (cpuTime, now)
            let previous = previousCPU[process.id]
            let elapsed = now.timeIntervalSince(previous?.date ?? now)
            let previousTime = previous?.time ?? cpuTime
            let delta = Double(cpuTime >= previousTime ? cpuTime - previousTime : 0)
            let percent = elapsed > 0 ? max(0, delta / 1_000_000_000 / elapsed * 100) : 0
            return ProcessSnapshot(
                id: process.id, name: process.name, path: process.path,
                parentID: process.parentID, userID: process.userID,
                userName: process.userName,
                virtualMemory: process.virtualMemory, residentMemory: process.residentMemory,
                threadCount: process.threadCount, startDate: process.startDate,
                cpuTimeNanoseconds: process.cpuTimeNanoseconds,
                cpuPercent: percent
            )
        }

        previousCPU = currentCPU
        return sampled
    }
}
