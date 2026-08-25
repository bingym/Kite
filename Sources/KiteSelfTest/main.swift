import Foundation
import KiteCore

let sample = ProcessSnapshot(id: 42, name: "Example", parentID: 1, residentMemory: 1024, cpuPercent: 12.5)
precondition(sample.id == 42)
precondition(sample.name == "Example")
precondition(sample.parentID == 1)
precondition(sample.residentMemory == 1024)
precondition(sample.cpuPercent == 12.5)

let processes = try MacOSProcessProvider().snapshot()
precondition(!processes.isEmpty, "The process provider returned no processes")
precondition(processes.contains(where: { $0.id == 0 }), "The process provider must retain PID 0")
precondition(processes.contains(where: { $0.name == "WindowServer" }), "WindowServer is missing")
if processes.contains(where: { $0.path?.contains("ViewBridgeAuxiliary") == true }) {
    precondition(processes.contains(where: { $0.name == "ViewBridgeAuxiliary" }), "ViewBridgeAuxiliary is truncated or missing")
}
precondition(processes.allSatisfy { !$0.userName.isEmpty }, "A process has no user name")

let memory = try MacOSMemoryProvider().snapshot()
precondition(memory.physicalMemory > 0, "Physical memory was not reported")
precondition(memory.memoryUsed <= memory.physicalMemory, "Used memory exceeds physical memory")
precondition((0...1).contains(memory.pressure), "Memory pressure is outside its normalized range")

let ports = try MacOSPortProvider().snapshot()
precondition(ports.allSatisfy { $0.localPort >= 0 && $0.localPort <= 65535 }, "A port snapshot has an invalid local port")
precondition(ports.allSatisfy { !$0.processName.isEmpty }, "A port snapshot has no process name")
precondition(ports.allSatisfy { $0.remotePort == nil || $0.remotePort! <= 65535 }, "A port snapshot has an invalid remote port")
print(
    "Self-test passed: \(processes.count) processes, \(memory.physicalMemory) bytes physical memory, "
        + "\(ports.count) local ports"
)
