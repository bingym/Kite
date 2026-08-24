import Foundation
import KiteCore

let processes = try MacOSProcessProvider().snapshot().sorted { $0.memoryFootprint > $1.memoryFootprint }
print("PID\tFOOTPRINT\tRESIDENT\tNAME")
for process in processes.prefix(20) {
    let footprint = ByteCountFormatter.string(fromByteCount: Int64(process.memoryFootprint), countStyle: .memory)
    let resident = ByteCountFormatter.string(fromByteCount: Int64(process.residentMemory), countStyle: .memory)
    print("\(process.id)\t\(footprint)\t\(resident)\t\(process.name)")
}
