import AppKit
import SwiftUI
import KiteCore

struct ContentView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case performance = "Performance"
        case processes = "Processes"
        var id: Self { self }
        var icon: String { self == .performance ? "waveform.path.ecg" : "list.bullet.rectangle" }
    }

    @StateObject private var model = ProcessViewModel()
    @State private var pendingAction: ConfirmedAction?
    @State private var expandedPIDs: Set<Int32> = []
    @State private var pinnedPIDs: [Int32] = []
    @State private var section = Section.processes

    var body: some View {
        VStack(spacing: 0) {
            appHeader
            Divider()
            mainContent
        }
        .frame(minWidth: 900, minHeight: 560)
        .task {
            await model.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await model.refresh()
            }
        }
        .alert("Operation Failed", isPresented: errorPresented) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            pendingAction?.title ?? "Confirm Action",
            isPresented: confirmationPresented,
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.buttonTitle, role: .destructive) {
                Task { await model.perform(action.action, on: action.process) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text("\(action.process.name) (PID \(action.process.id))")
        }
    }

    private var appHeader: some View {
        HStack(spacing: 14) {
            KiteMark().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 0) {
            Text("Kite").font(.headline)
                Text(section == .processes ? "All Processes" : "System Performance")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)

            Spacer()
            Picker("View", selection: $section) {
                ForEach(Section.allCases) { item in Text(item.rawValue).tag(item) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 250)
            Spacer()

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(width: 250, height: 30)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .opacity(section == .processes ? 1 : 0)
            .allowsHitTesting(section == .processes)
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(.bar)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch section {
        case .performance:
            PerformanceView(model: model)
        case .processes:
            processesView
        }
    }

    private var processesView: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider()
            HSplitView {
                processTable.frame(minWidth: 650)
                detailPane.frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 18) {
            Label("\(model.visibleProcesses.count) Processes", systemImage: "list.bullet.rectangle")
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Text("Live update")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(.bar)
    }

    private var processTable: some View {
        VStack(spacing: 0) {
            ProcessColumns { title, width, alignment in
                if let sort = sortOption(for: title) {
                    HStack(spacing: 4) {
                        if alignment == .trailing { Spacer(minLength: 0) }
                        Text(title)
                        if model.sort == sort {
                            Image(systemName: model.sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        if alignment != .trailing { Spacer(minLength: 0) }
                    }
                    .contentShape(Rectangle())
                        .frame(width: width, alignment: alignment)
                    .onTapGesture { model.selectSort(sort) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Sort by \(title)")
                } else {
                    Text(title).frame(width: width, alignment: alignment)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.bar)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.treeRows(expandedPIDs: expandedPIDs, pinnedPIDs: pinnedPIDs)) { row in
                        ProcessColumns { column, width, alignment in
                            processColumn(column, row: row)
                                .frame(width: width, alignment: alignment)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(
                            model.selectedPID == row.process.id
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { model.selectedPID = row.process.id }
                        .contextMenu { processMenu(for: row.process) }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(model.selectedPID == row.process.id ? .isSelected : [])

                        Divider().padding(.leading, 10)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }


    @ViewBuilder
    private func processColumn(_ column: String, row: ProcessTreeRow) -> some View {
        let process = row.process
        switch column {
        case "Process Name":
            HStack(spacing: 6) {
                Color.clear.frame(width: CGFloat(row.depth) * 16)
                if row.hasChildren {
                    Button {
                        if expandedPIDs.contains(process.id) {
                            expandedPIDs.remove(process.id)
                        } else {
                            expandedPIDs.insert(process.id)
                        }
                    } label: {
                        Image(systemName: expandedPIDs.contains(process.id) || !model.query.isEmpty
                              ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 12, height: 20)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12)
                }
                ProcessIcon(process: process)
                if row.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Text(process.name).lineLimit(1)
                Spacer(minLength: 0)
            }
        case "PID":
            Text(process.id, format: .number.grouping(.never)).monospacedDigit().foregroundStyle(.secondary)
        case "CPU":
            Text(process.cpuPercent, format: .number.precision(.fractionLength(1))) + Text("%")
        case "Memory":
            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: process.memoryFootprint), countStyle: .memory))
        case "Resident":
            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: process.residentMemory), countStyle: .memory))
        case "Threads":
            Text(process.threadCount, format: .number)
        default:
            Text(process.userName).lineLimit(1).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func processMenu(for process: ProcessSnapshot) -> some View {
        if pinnedPIDs.contains(process.id) {
            Button("Unpin") { pinnedPIDs.removeAll { $0 == process.id } }
        } else {
            Button("Pin") { pinnedPIDs.append(process.id) }
        }
        Divider()
        Button("End Task") {
            model.selectedPID = process.id
            pendingAction = ConfirmedAction(action: .terminate, process: process)
        }
        Button("Force Quit") {
            model.selectedPID = process.id
            pendingAction = ConfirmedAction(action: .forceTerminate, process: process)
        }
        Divider()
        Button("Open File Location") { revealInFinder(process) }
            .disabled(process.path == nil)
        Divider()
        Button("End Process Tree") {
            model.selectedPID = process.id
            pendingAction = ConfirmedAction(action: .endTree, process: process)
        }
    }

    private func revealInFinder(_ process: ProcessSnapshot) {
        guard let path = process.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func sortOption(for column: String) -> ProcessSort? {
        switch column {
        case "Process Name": .name
        case "PID": .pid
        case "CPU": .cpu
        case "Memory": .memory
        case "Resident": .memory
        case "Threads": .threads
        case "User": .user
        default: nil
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let process = model.selectedProcess {
            ProcessDetailView(process: process) { action in
                switch action {
                case .terminate, .forceTerminate, .endTree:
                    pendingAction = ConfirmedAction(action: action, process: process)
                case .pause, .resume:
                    Task { await model.perform(action, on: process) }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("No Process Selected")
                    .font(.headline)
                Text("Select a process from the list to view details")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
    }
}

private struct KiteMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(red: 0.12, green: 0.72, blue: 0.58))
            Path { path in
                path.move(to: CGPoint(x: 6, y: 21))
                path.addCurve(to: CGPoint(x: 29, y: 12), control1: CGPoint(x: 12, y: 8), control2: CGPoint(x: 22, y: 28))
                path.move(to: CGPoint(x: 29, y: 12))
                path.addLine(to: CGPoint(x: 24, y: 12))
                path.move(to: CGPoint(x: 29, y: 12))
                path.addLine(to: CGPoint(x: 28, y: 17))
            }
            .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            Circle().fill(.white).frame(width: 4, height: 4).offset(x: -8, y: -8)
        }
        .accessibilityHidden(true)
    }
}

private struct ProcessColumns<Content: View>: View {
    let content: (String, CGFloat?, Alignment) -> Content
    init(@ViewBuilder content: @escaping (String, CGFloat?, Alignment) -> Content) {
        self.content = content
    }

    var body: some View {
        HStack(spacing: 12) {
            content("Process Name", nil, .leading).frame(maxWidth: .infinity, alignment: .leading)
            content("PID", 60, .trailing)
            content("CPU", 70, .trailing)
            content("Memory", 90, .trailing)
            content("Resident", 90, .trailing)
            content("Threads", 58, .trailing)
            content("User", 104, .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct ProcessIcon: View {
    let process: ProcessSnapshot

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
    }

    private var icon: NSImage {
        if let running = NSRunningApplication(processIdentifier: pid_t(process.id)),
           let icon = running.icon {
            return icon
        }
        guard let path = process.path else {
            return NSWorkspace.shared.icon(for: .unixExecutable)
        }
        if let appURL = containingApplication(for: URL(fileURLWithPath: path)) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private func containingApplication(for executableURL: URL) -> URL? {
        var candidate = executableURL
        while candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }
}

private struct ConfirmedAction: Identifiable {
    let action: ProcessAction
    let process: ProcessSnapshot
    let id = UUID()

    var title: String {
        switch action {
        case .forceTerminate: "Force Quit Process?"
        case .endTree: "End Process Tree?"
        default: "End Task?"
        }
    }

    var buttonTitle: String {
        switch action {
        case .forceTerminate: "Force Quit"
        case .endTree: "End Process Tree"
        default: "End Task"
        }
    }
}
