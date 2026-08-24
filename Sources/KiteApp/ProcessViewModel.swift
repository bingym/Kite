import Foundation
import KiteCore

enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case name
    case pid
    case threads
    case user

    var id: Self { self }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .name: "Name"
        case .pid: "PID"
        case .threads: "Threads"
        case .user: "User"
        }
    }
}

enum ProcessAction: Sendable {
    case terminate
    case forceTerminate
    case pause
    case resume
    case endTree
}

struct ProcessTreeRow: Identifiable {
    let process: ProcessSnapshot
    let depth: Int
    let hasChildren: Bool
    let isPinned: Bool

    var id: Int32 { process.id }
}

actor ProcessService {
    private let sampler = ProcessSampler()
    private let memoryProvider = MacOSMemoryProvider()
    private let cpuSampler = MacOSCPUSampler()
    private let controller = MacOSProcessController()

    func sample() throws -> ([ProcessSnapshot], MemorySnapshot, CPUSnapshot) {
        (try sampler.sample(), try memoryProvider.snapshot(), try cpuSampler.sample())
    }

    func perform(_ action: ProcessAction, pid: Int32) throws {
        switch action {
        case .terminate: try controller.terminate(pid: pid)
        case .forceTerminate: try controller.forceTerminate(pid: pid)
        case .pause: try controller.pause(pid: pid)
        case .resume: try controller.resume(pid: pid)
        case .endTree: break
        }
    }

    func endProcessTree(pids: [Int32]) throws {
        var firstError: Error?
        for pid in pids {
            do {
                try controller.terminate(pid: pid)
            } catch let error as POSIXError where error.code == .ESRCH {
                continue
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}

@MainActor
final class ProcessViewModel: ObservableObject {
    @Published private(set) var processes: [ProcessSnapshot] = []
    @Published private(set) var memory: MemorySnapshot?
    @Published private(set) var pressureHistory: [Double] = []
    @Published private(set) var cpu: CPUSnapshot?
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryHistory: [Double] = []
    @Published var selectedPID: Int32?
    @Published var query = ""
    @Published var sort = ProcessSort.cpu
    @Published var sortAscending = false
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?

    private let service = ProcessService()

    var visibleProcesses: [ProcessSnapshot] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = processes.filter { $0.id != 0 }
        let filtered = needle.isEmpty ? candidates : candidates.filter { process in
            process.name.localizedCaseInsensitiveContains(needle)
                || process.path?.localizedCaseInsensitiveContains(needle) == true
                || String(process.id).contains(needle)
                || String(process.userID).contains(needle)
                || process.userName.localizedCaseInsensitiveContains(needle)
        }
        return filtered.sorted(by: comesBefore)
    }

    var selectedProcess: ProcessSnapshot? {
        guard let selectedPID else { return nil }
        return processes.first { $0.id == selectedPID }
    }

    var totalResidentMemory: UInt64 {
        processes.reduce(0) { $0 &+ $1.residentMemory }
    }

    var parentPIDs: Set<Int32> {
        let knownPIDs = Set(processes.map(\.id))
        return Set(processes.compactMap { process in
            guard process.parentID != process.id, knownPIDs.contains(process.parentID) else { return nil }
            return process.parentID
        })
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let sample = try await service.sample()
            processes = sample.0
            memory = sample.1
            cpu = sample.2
            pressureHistory.append(sample.1.pressure)
            cpuHistory.append(sample.2.totalPercent / 100)
            memoryHistory.append(sample.1.pressure)
            trimHistory(&pressureHistory)
            trimHistory(&cpuHistory)
            trimHistory(&memoryHistory)
            errorMessage = nil
            if let selectedPID, !processes.contains(where: { $0.id == selectedPID }) {
                self.selectedPID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trimHistory(_ history: inout [Double]) {
        if history.count > 30 { history.removeFirst(history.count - 30) }
    }

    func perform(_ action: ProcessAction, on process: ProcessSnapshot) async {
        do {
            if action == .endTree {
                try await service.endProcessTree(pids: processTreePIDs(rootPID: process.id))
            } else {
                try await service.perform(action, pid: process.id)
            }
            try? await Task.sleep(for: .milliseconds(250))
            await refresh()
        } catch {
            errorMessage = "Could not control \(process.name) (PID \(process.id)): \(error.localizedDescription)"
        }
    }

    func treeRows(expandedPIDs: Set<Int32>, pinnedPIDs: [Int32]) -> [ProcessTreeRow] {
        let processByID = Dictionary(uniqueKeysWithValues: processes.filter { $0.id != 0 }.map { ($0.id, $0) })
        var children: [Int32: [ProcessSnapshot]] = [:]
        for process in processes where process.id != 0 && process.parentID > 1 && process.parentID != process.id && processByID[process.parentID] != nil {
            children[process.parentID, default: []].append(process)
        }

        let allowedIDs: Set<Int32>?
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty {
            allowedIDs = nil
        } else {
            var included = Set(processes.filter { matches($0, needle: needle) }.map(\.id))
            for matchedID in included {
                var currentID = matchedID
                var seen = Set<Int32>()
                while let process = processByID[currentID], seen.insert(currentID).inserted,
                      process.parentID > 1, process.parentID != currentID, processByID[process.parentID] != nil {
                    included.insert(process.parentID)
                    currentID = process.parentID
                }
            }
            allowedIDs = included
        }

        let roots = processes.filter {
            $0.id != 0 && ($0.id <= 1 || $0.parentID <= 1 || $0.parentID == $0.id || processByID[$0.parentID] == nil)
        }.sorted(by: comesBefore)
        var rows: [ProcessTreeRow] = []
        var visited = Set<Int32>()

        func append(_ process: ProcessSnapshot, depth: Int, isPinned: Bool = false) {
            guard visited.insert(process.id).inserted else { return }
            guard allowedIDs?.contains(process.id) ?? true else { return }
            let visibleChildren = (children[process.id] ?? [])
                .filter { allowedIDs?.contains($0.id) ?? true }
                .sorted(by: comesBefore)
            rows.append(ProcessTreeRow(process: process, depth: depth, hasChildren: !visibleChildren.isEmpty, isPinned: isPinned))
            if expandedPIDs.contains(process.id) || allowedIDs != nil {
                for child in visibleChildren { append(child, depth: depth + 1) }
            }
        }

        for pid in pinnedPIDs {
            if let process = processByID[pid] { append(process, depth: 0, isPinned: true) }
        }
        for root in roots { append(root, depth: 0) }
        return rows
    }

    private func processTreePIDs(rootPID: Int32) -> [Int32] {
        let children = Dictionary(grouping: processes, by: \.parentID)
        var result: [Int32] = []
        var visited = Set<Int32>()
        func visit(_ pid: Int32) {
            guard visited.insert(pid).inserted else { return }
            for child in children[pid] ?? [] where child.id != pid { visit(child.id) }
            result.append(pid)
        }
        visit(rootPID)
        return result
    }

    private func matches(_ process: ProcessSnapshot, needle: String) -> Bool {
        process.name.localizedCaseInsensitiveContains(needle)
            || process.path?.localizedCaseInsensitiveContains(needle) == true
            || String(process.id).contains(needle)
            || String(process.userID).contains(needle)
            || process.userName.localizedCaseInsensitiveContains(needle)
    }

    func selectSort(_ newSort: ProcessSort) {
        if sort == newSort {
            sortAscending.toggle()
        } else {
            sort = newSort
            sortAscending = newSort == .name || newSort == .user || newSort == .pid
        }
    }

    private func comesBefore(_ lhs: ProcessSnapshot, _ rhs: ProcessSnapshot) -> Bool {
        let comparison: ComparisonResult
        switch sort {
        case .cpu:
            comparison = compare(lhs.cpuPercent, rhs.cpuPercent, lhs.id, rhs.id)
        case .memory:
            comparison = compare(lhs.memoryFootprint, rhs.memoryFootprint, lhs.id, rhs.id)
        case .name:
            let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
            comparison = nameComparison == .orderedSame ? compare(lhs.id, rhs.id, lhs.id, rhs.id) : nameComparison
        case .pid:
            comparison = lhs.id == rhs.id ? .orderedSame : (lhs.id < rhs.id ? .orderedAscending : .orderedDescending)
        case .threads:
            comparison = compare(lhs.threadCount, rhs.threadCount, lhs.id, rhs.id)
        case .user:
            let userComparison = lhs.userName.localizedStandardCompare(rhs.userName)
            comparison = userComparison == .orderedSame ? compare(lhs.id, rhs.id, lhs.id, rhs.id) : userComparison
        }
        return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private func compare<T: Comparable>(_ lhs: T, _ rhs: T, _ lhsPID: Int32, _ rhsPID: Int32) -> ComparisonResult {
        if lhs == rhs {
            if lhsPID == rhsPID { return .orderedSame }
            return lhsPID < rhsPID ? .orderedAscending : .orderedDescending
        }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }
}
