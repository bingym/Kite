import SwiftUI
import KiteCore

struct PerformanceView: View {
    private enum Metric: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"
        var id: Self { self }
        var icon: String { self == .cpu ? "cpu" : "memorychip" }
        var color: Color { self == .cpu ? .cyan : .purple }
    }

    @ObservedObject var model: ProcessViewModel
    @State private var metric = Metric.cpu

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
                Text("Live · 60 seconds").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .frame(height: 48)
            Divider()
            Group {
                switch metric {
                case .cpu: cpuDetail
                case .memory: memoryDetail
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

    private var cpuDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            performanceHeader("CPU", value: percent(model.cpu?.totalPercent ?? 0), subtitle: "Overall utilization")
            RealtimeGraph(values: model.cpuHistory, color: .cyan)
                .frame(minHeight: 240)
            Text("60 seconds").font(.caption).foregroundStyle(.secondary)
            if let cpu = model.cpu {
                LazyVGrid(columns: statColumns, alignment: .leading, spacing: 16) {
                    stat("Utilization", percent(cpu.totalPercent))
                    stat("User", percent(cpu.userPercent))
                    stat("System", percent(cpu.systemPercent))
                    stat("Idle", percent(cpu.idlePercent))
                    stat("Logical Processors", cpu.logicalProcessorCount.formatted())
                    stat("Processes", model.processes.count.formatted())
                    stat("Threads", model.processes.reduce(0) { $0 + Int($1.threadCount) }.formatted())
                    stat("Uptime", Duration.seconds(ProcessInfo.processInfo.systemUptime).formatted(.time(pattern: .hourMinuteSecond)))
                }
            }
        }
        .padding(24)
    }

    private var memoryDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            performanceHeader("Memory", value: percent((model.memory?.pressure ?? 0) * 100), subtitle: memoryCapacity)
            RealtimeGraph(values: model.memoryHistory, color: .purple)
                .frame(minHeight: 240)
            Text("60 seconds").font(.caption).foregroundStyle(.secondary)
            if let memory = model.memory {
                LazyVGrid(columns: statColumns, alignment: .leading, spacing: 16) {
                    stat("In Use", bytes(memory.memoryUsed))
                    stat("Available", bytes(memory.physicalMemory - min(memory.memoryUsed, memory.physicalMemory)))
                    stat("Physical Memory", bytes(memory.physicalMemory))
                    stat("Cached", bytes(memory.cachedFiles))
                    stat("App Memory", bytes(memory.appMemory))
                    stat("Wired", bytes(memory.wiredMemory))
                    stat("Compressed", bytes(memory.compressedMemory))
                    stat("Swap Used", bytes(memory.swapUsed))
                    stat("Swap Total", bytes(memory.swapTotal))
                    stat("Page Ins", memory.pageIns.formatted())
                    stat("Page Outs", memory.pageOuts.formatted())
                    stat("Pressure", pressureLabel(memory.pressure))
                }
            }
        }
        .padding(24)
    }

    private var statColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    }

    private func performanceHeader(_ title: String, value: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 34, weight: .semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            Text(value).font(.system(size: 28, weight: .medium)).monospacedDigit()
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    private var memoryCapacity: String {
        guard let memory = model.memory else { return "Loading..." }
        return "\(bytes(memory.memoryUsed)) used of \(bytes(memory.physicalMemory))"
    }
    private func percent(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) + "%" }
    private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory) }
    private func pressureLabel(_ pressure: Double) -> String { pressure >= 0.9 ? "Critical" : (pressure >= 0.7 ? "Warning" : "Normal") }
}

private struct RealtimeGraph: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                GridLines().stroke(color.opacity(0.16), lineWidth: 1)
                line(in: geometry.size).stroke(color, lineWidth: 2)
            }
            .background(color.opacity(0.035))
            .overlay(Rectangle().stroke(color.opacity(0.7), lineWidth: 1))
        }
        .accessibilityLabel("Real-time utilization graph")
    }

    private func line(in size: CGSize) -> Path {
        let samples = values.isEmpty ? [0] : values
        var path = Path()
        for (index, value) in samples.enumerated() {
            let x = samples.count == 1 ? size.width : size.width * CGFloat(index) / CGFloat(samples.count - 1)
            let y = size.height * (1 - CGFloat(min(max(value, 0), 1)))
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0...10 {
            let x = rect.width * CGFloat(index) / 10
            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        for index in 0...6 {
            let y = rect.height * CGFloat(index) / 6
            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}
