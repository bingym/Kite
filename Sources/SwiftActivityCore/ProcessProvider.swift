import Foundation
import Darwin

public protocol ProcessProvider: Sendable {
    func snapshot() throws -> [ProcessSnapshot]
}

public enum ProcessProviderError: Error, Equatable {
    case processListUnavailable
}

public struct MacOSProcessProvider: ProcessProvider {
    public init() {}

    public func snapshot() throws -> [ProcessSnapshot] {
        let byteCount = proc_listallpids(nil, 0)
        guard byteCount > 0 else { throw ProcessProviderError.processListUnavailable }

        var pids = [Int32](repeating: 0, count: Int(byteCount) + 32)
        let pidBytes = Int32(pids.count * MemoryLayout<Int32>.stride)
        let result = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, pidBytes)
        }
        guard result > 0 else { throw ProcessProviderError.processListUnavailable }

        var uniquePIDs = Set(pids.prefix(Int(result)).filter { $0 >= 0 })
        uniquePIDs.insert(0)
        let kernelResidentMemory = (try? MacOSMemoryProvider().snapshot().memoryUsed) ?? 0
        return uniquePIDs.map { readProcess($0, kernelResidentMemory: kernelResidentMemory) }
    }

    private func readProcess(_ pid: Int32, kernelResidentMemory: UInt64) -> ProcessSnapshot {
        var bsdInfo = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let hasBSDInfo = pid > 0 && proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize
        var shortInfo = proc_bsdshortinfo()
        let shortSize = Int32(MemoryLayout<proc_bsdshortinfo>.stride)
        let hasShortInfo = pid > 0
            && proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &shortInfo, shortSize) == shortSize

        var taskInfo = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        let hasTaskInfo = pid > 0 && proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize) == taskSize
        let discoveredName = processName(pid)
        let bsdName = hasBSDInfo ? cString(bsdInfo.pbi_name) : ""
        let shortName = hasShortInfo ? cString(shortInfo.pbsi_comm) : ""
        let fallbackName = !bsdName.isEmpty ? bsdName : (!shortName.isEmpty ? shortName : "Process \(pid)")
        let name = pid == 0 ? "kernel_task" : (discoveredName ?? fallbackName)
        let userID = hasBSDInfo ? bsdInfo.pbi_uid : (hasShortInfo ? shortInfo.pbsi_uid : 0)
        let parentID = hasBSDInfo ? Int32(bsdInfo.pbi_ppid) : (hasShortInfo ? Int32(shortInfo.pbsi_ppid) : 0)
        let startDate = hasBSDInfo
            ? Date(timeIntervalSince1970: TimeInterval(bsdInfo.pbi_start_tvsec) + TimeInterval(bsdInfo.pbi_start_tvusec) / 1_000_000)
            : nil

        return ProcessSnapshot(
            id: pid,
            name: name,
            path: pid > 0 ? processPath(pid) : nil,
            parentID: parentID,
            userID: userID,
            userName: userName(for: userID),
            virtualMemory: hasTaskInfo ? taskInfo.pti_virtual_size : 0,
            residentMemory: pid == 0 ? kernelResidentMemory : (hasTaskInfo ? taskInfo.pti_resident_size : 0),
            threadCount: hasTaskInfo ? taskInfo.pti_threadnum : 0,
            startDate: startDate,
            cpuTimeNanoseconds: hasTaskInfo ? taskInfo.pti_total_user &+ taskInfo.pti_total_system : 0,
            cpuPercent: 0
        )
    }

    private func userName(for userID: UInt32) -> String {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        let suggestedSize = sysconf(_SC_GETPW_R_SIZE_MAX)
        let bufferSize = suggestedSize > 0 ? Int(suggestedSize) : 16_384
        var buffer = [CChar](repeating: 0, count: bufferSize)
        let status = getpwuid_r(uid_t(userID), &entry, &buffer, buffer.count, &result)
        guard status == 0, result != nil, let name = entry.pw_name else {
            return String(userID)
        }
        let length = strlen(name)
        let bytes = UnsafeRawPointer(name).assumingMemoryBound(to: UInt8.self)
        return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
    }

    private func processName(_ pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 1024)
        let length = buffer.withUnsafeMutableBufferPointer {
            proc_name(pid, $0.baseAddress, UInt32($0.count))
        }
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func processPath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = buffer.withUnsafeMutableBufferPointer {
            proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
        }
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func cString<T>(_ value: T) -> String {
        withUnsafeBytes(of: value) { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
            return String(decoding: bytes[..<end], as: UTF8.self)
        }
    }
}
