import Darwin
import Foundation

public struct MemorySnapshot: Equatable, Sendable {
    public let physicalMemory: UInt64
    public let memoryUsed: UInt64
    public let cachedFiles: UInt64
    public let swapUsed: UInt64
    public let swapTotal: UInt64
    public let appMemory: UInt64
    public let wiredMemory: UInt64
    public let compressedMemory: UInt64
    public let pressure: Double
    public let pageIns: UInt64
    public let pageOuts: UInt64

    public init(
        physicalMemory: UInt64,
        memoryUsed: UInt64,
        cachedFiles: UInt64,
        swapUsed: UInt64,
        swapTotal: UInt64,
        appMemory: UInt64,
        wiredMemory: UInt64,
        compressedMemory: UInt64,
        pressure: Double,
        pageIns: UInt64,
        pageOuts: UInt64
    ) {
        self.physicalMemory = physicalMemory
        self.memoryUsed = memoryUsed
        self.cachedFiles = cachedFiles
        self.swapUsed = swapUsed
        self.swapTotal = swapTotal
        self.appMemory = appMemory
        self.wiredMemory = wiredMemory
        self.compressedMemory = compressedMemory
        self.pressure = pressure
        self.pageIns = pageIns
        self.pageOuts = pageOuts
    }
}

public protocol MemoryProvider: Sendable {
    func snapshot() throws -> MemorySnapshot
}

public enum MemoryProviderError: Error {
    case statisticsUnavailable(kern_return_t)
}

public struct MacOSMemoryProvider: MemoryProvider {
    public init() {}

    public func snapshot() throws -> MemorySnapshot {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MemoryProviderError.statisticsUnavailable(result)
        }

        var hostPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &hostPageSize) == KERN_SUCCESS else {
            throw MemoryProviderError.statisticsUnavailable(KERN_FAILURE)
        }
        let pageSize = UInt64(hostPageSize)
        let physical = ProcessInfo.processInfo.physicalMemory
        let cached = pages(statistics.external_page_count &+ statistics.purgeable_count, pageSize: pageSize)
        let wired = pages(statistics.wire_count, pageSize: pageSize)
        let compressed = pages(statistics.compressor_page_count, pageSize: pageSize)
        let appPages = statistics.internal_page_count > statistics.purgeable_count
            ? statistics.internal_page_count - statistics.purgeable_count
            : 0
        let app = pages(appPages, pageSize: pageSize)
        let pressureBytes = min(physical, app &+ wired &+ compressed)
        let used = pressureBytes

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let hasSwap = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0

        return MemorySnapshot(
            physicalMemory: physical,
            memoryUsed: used,
            cachedFiles: cached,
            swapUsed: hasSwap ? swap.xsu_used : 0,
            swapTotal: hasSwap ? swap.xsu_total : 0,
            appMemory: app,
            wiredMemory: wired,
            compressedMemory: compressed,
            pressure: physical > 0 ? Double(pressureBytes) / Double(physical) : 0,
            pageIns: statistics.pageins,
            pageOuts: statistics.pageouts
        )
    }

    private func pages<T: BinaryInteger>(_ count: T, pageSize: UInt64) -> UInt64 {
        UInt64(count) &* pageSize
    }
}
