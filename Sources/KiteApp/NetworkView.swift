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

    @ObservedObject var model: ProcessViewModel
    @State private var metric = Metric.ports
    @State private var sort: PortSort = .port
    @State private var sortAscending = true

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
                Text("\(model.ports.count) local ports · Live · 60 seconds").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .frame(height: 48)
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

    private var sortedPorts: [PortSnapshot] {
        let ordered = model.ports.sorted { lhs, rhs in
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
                Text("Local Address").frame(minWidth: 130, alignment: .leading)
                Text("Remote Address").frame(minWidth: 150, alignment: .leading)
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
                LazyVStack(spacing: 0) {
                    ForEach(sortedPorts) { port in
                        HStack(spacing: 12) {
                            Text(String(port.localPort)).monospacedDigit().frame(width: 90, alignment: .trailing)
                            Text(port.transport.rawValue).frame(width: 70, alignment: .leading)
                            Text(port.state ?? "—").lineLimit(1).frame(width: 110, alignment: .leading)
                            Text("\(port.localAddress):\(port.localPort)").monospacedDigit().lineLimit(1).frame(minWidth: 130, alignment: .leading)
                            Text(port.remoteAddress.map { "\($0):\(port.remotePort ?? 0)" } ?? "—").monospacedDigit().lineLimit(1).foregroundStyle(.secondary).frame(minWidth: 150, alignment: .leading)
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
