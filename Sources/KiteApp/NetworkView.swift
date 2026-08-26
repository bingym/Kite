import SwiftUI
import KiteCore

struct NetworkView: View {
    private enum Metric: String, CaseIterable, Identifiable {
        case ports = "Port"
        var id: Self { self }
        var icon: String { "point.3.filled.connected.trianglepath.dotted" }
    }

    private enum PortSort: String, CaseIterable {
        case port
        case processName = "Process Name"
        case pid = "PID"
    }

    private enum ProtocolFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case tcp = "TCP"
        case udp = "UDP"
        var id: String { rawValue }
    }

    private enum StateFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case listen = "Listen"
        case established = "Established"
        case synSent = "SYN Sent"
        case synReceived = "SYN Received"
        case closeWait = "Close Wait"
        case finWait1 = "FIN Wait 1"
        case finWait2 = "FIN Wait 2"
        case closing = "Closing"
        case lastAck = "Last ACK"
        case timeWait = "Time Wait"
        case closed = "Closed"
        case none = "—"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: "— (No State)"
            default: rawValue
            }
        }
    }

    @ObservedObject var model: ProcessViewModel
    @State private var metric = Metric.ports
    @State private var sort: PortSort = .port
    @State private var sortAscending = true
    @State private var protocolFilter: ProtocolFilter = .all
    @State private var stateFilter: StateFilter = .all

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Metric", selection: $metric) {
                    ForEach(Metric.allCases) { item in
                        Label(item.rawValue, systemImage: item.icon).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
                Spacer()
                Text(filteredSummary).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .frame(height: 48)
            Divider()
            filterBar
            Divider()
            Group {
                switch metric {
                case .ports: portDetail
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("\(model.processes.count) processes")
                Spacer()
                Text("Live update")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 28)
        }
    }

    private var hasActiveFilters: Bool {
        protocolFilter != .all || stateFilter != .all
    }

    private var filteredSummary: String {
        if !hasActiveFilters {
            return "\(model.ports.count) local ports · Live · 60 seconds"
        }
        return "\(sortedPorts.count) of \(model.ports.count) local ports · Live"
    }

    private var activeFilterDescription: String {
        var parts: [String] = []
        if protocolFilter != .all { parts.append("Protocol: \(protocolFilter.rawValue)") }
        if stateFilter != .all { parts.append("State: \(stateFilter.label)") }
        return parts.joined(separator: " · ")
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Text("Protocol:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Protocol", selection: $protocolFilter) {
                ForEach(ProtocolFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 160)

            Text("State:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            Picker("State", selection: $stateFilter) {
                ForEach(StateFilter.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 170)

            Spacer()

            if hasActiveFilters {
                Button("Clear Filters") {
                    protocolFilter = .all
                    stateFilter = .all
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    private var sortedPorts: [PortSnapshot] {
        let filtered = model.ports.filter { port in
            let protocolMatches: Bool = {
                switch protocolFilter {
                case .all: return true
                case .tcp: return port.transport == .tcp
                case .udp: return port.transport == .udp
                }
            }()
            let stateMatches: Bool = {
                switch stateFilter {
                case .all: return true
                case .none: return port.state == nil
                default: return port.state == stateFilter.rawValue
                }
            }()
            return protocolMatches && stateMatches
        }
        let ordered = filtered.sorted { lhs, rhs in
            let result: ComparisonResult
            switch sort {
            case .port:
                result = lhs.localPort == rhs.localPort ? comparePIDs(lhs, rhs)
                    : (lhs.localPort < rhs.localPort ? .orderedAscending : .orderedDescending)
            case .processName:
                let nameComparison = lhs.processName.localizedStandardCompare(rhs.processName)
                result = nameComparison == .orderedSame ? comparePIDs(lhs, rhs) : nameComparison
            case .pid:
                result = comparePIDs(lhs, rhs)
            }
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
        return ordered
    }

    private func comparePIDs(_ lhs: PortSnapshot, _ rhs: PortSnapshot) -> ComparisonResult {
        lhs.pid == rhs.pid ? .orderedSame : (lhs.pid < rhs.pid ? .orderedAscending : .orderedDescending)
    }

    private var portDetail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                sortHeader("Port", width: 90, alignment: .trailing, for: .port)
                Text("Protocol").frame(width: 70, alignment: .leading)
                Text("State").frame(width: 110, alignment: .leading)
                Text("Local Address").frame(width: 220, alignment: .leading)
                Text("Remote Address").frame(width: 240, alignment: .leading)
                sortHeader("PID", width: 60, alignment: .trailing, for: .pid)
                sortHeader("Process Name", width: nil, alignment: .leading, for: .processName)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(.bar)

            Divider()

            ScrollView {
                if sortedPorts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("No ports match filters")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if hasActiveFilters {
                            Text(activeFilterDescription)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedPorts) { port in
                            HStack(spacing: 12) {
                                Text(String(port.localPort)).monospacedDigit().frame(width: 90, alignment: .trailing)
                                Text(port.transport.rawValue).frame(width: 70, alignment: .leading)
                                Text(port.state ?? "—").lineLimit(1).frame(width: 110, alignment: .leading)
                                Text("\(port.localAddress):\(port.localPort)").monospacedDigit().lineLimit(1).truncationMode(.middle).frame(width: 220, alignment: .leading)
                                    .help("\(port.localAddress):\(port.localPort)")
                                Text(port.remoteAddress.map { "\($0):\(port.remotePort ?? 0)" } ?? "—").monospacedDigit().lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary).frame(width: 240, alignment: .leading)
                                    .help(port.remoteAddress.map { "\($0):\(port.remotePort ?? 0)" } ?? "")
                                Text(port.pid, format: .number.grouping(.never)).monospacedDigit().foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                                Text(port.processName).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.callout.monospacedDigit())
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                            Divider().padding(.leading, 10)
                        }
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func sortHeader(_ title: String, width: CGFloat?, alignment: Alignment, for sortOption: PortSort) -> some View {
        HStack(spacing: 4) {
            if alignment == .trailing { Spacer(minLength: 0) }
            Text(title)
            if sort == sortOption {
                Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            if alignment != .trailing { Spacer(minLength: 0) }
        }
        .frame(width: width, alignment: alignment)
        .contentShape(Rectangle())
        .onTapGesture { selectSort(sortOption) }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Sort by \(title)")
    }

    private func selectSort(_ newSort: PortSort) {
        if sort == newSort {
            sortAscending.toggle()
        } else {
            sort = newSort
            sortAscending = true
        }
    }
}
