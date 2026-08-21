import Foundation
import SwiftActivityCore

let sample = ProcessSnapshot(id: 42, name: "Example", parentID: 1, residentMemory: 1024, cpuPercent: 12.5)
precondition(sample.id == 42)
precondition(sample.name == "Example")
precondition(sample.parentID == 1)
precondition(sample.residentMemory == 1024)
precondition(sample.cpuPercent == 12.5)

let processes = try MacOSProcessProvider().snapshot()
precondition(!processes.isEmpty, "The process provider returned no processes")
precondition(processes.contains(where: { $0.id == 0 }), "The kernel task is missing")
precondition(processes.contains(where: { $0.name == "kernel_task" }), "kernel_task is missing by name")
precondition(processes.first(where: { $0.id == 0 })?.residentMemory ?? 0 > 0, "kernel_task memory is missing")
precondition(processes.contains(where: { $0.name == "WindowServer" }), "WindowServer is missing")
if processes.contains(where: { $0.path?.contains("ViewBridgeAuxiliary") == true }) {
    precondition(processes.contains(where: { $0.name == "ViewBridgeAuxiliary" }), "ViewBridgeAuxiliary is truncated or missing")
}
precondition(processes.allSatisfy { !$0.userName.isEmpty }, "A process has no user name")

let memory = try MacOSMemoryProvider().snapshot()
precondition(memory.physicalMemory > 0, "Physical memory was not reported")
precondition(memory.memoryUsed <= memory.physicalMemory, "Used memory exceeds physical memory")
precondition((0...1).contains(memory.pressure), "Memory pressure is outside its normalized range")
print("Self-test passed: \(processes.count) processes, \(memory.physicalMemory) bytes physical memory")
