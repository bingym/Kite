import Foundation
import SwiftActivityCore

let processes = try MacOSProcessProvider().snapshot().sorted { $0.residentMemory > $1.residentMemory }
print("PID\tMEMORY\tNAME")
for process in processes.prefix(20) {
    let memory = ByteCountFormatter.string(fromByteCount: Int64(process.residentMemory), countStyle: .memory)
    print("\(process.id)\t\(memory)\t\(process.name)")
}
