import SwiftUI
import KiteCore

struct ProcessDetailView: View {
    let process: ProcessSnapshot
    let perform: (ProcessAction) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(process.name)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    Text("PID \(process.id)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button { perform(.pause) } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    Button { perform(.resume) } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 11) {
                    detailRow("CPU", value: process.cpuPercent.formatted(.number.precision(.fractionLength(1))) + "%")
                    detailRow("Resident Memory", value: bytes(process.residentMemory))
                    detailRow("Virtual Memory", value: bytes(process.virtualMemory))
                    detailRow("Threads", value: process.threadCount.formatted())
                    detailRow("Parent PID", value: process.parentID.formatted(.number.grouping(.never)))
                    detailRow("User", value: process.userName)
                    detailRow("User ID", value: process.userID.formatted(.number.grouping(.never)))
                    detailRow("CPU Time", value: cpuTime)
                    detailRow("Started", value: startDate)
                }

                if let path = process.path {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Executable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(path)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()
                HStack {
                    Button("Quit", role: .destructive) { perform(.terminate) }
                    Spacer()
                    Button("Force Quit", role: .destructive) { perform(.forceTerminate) }
                }
            }
            .padding(20)
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private var cpuTime: String {
        Duration.nanoseconds(Int64(clamping: process.cpuTimeNanoseconds))
            .formatted(.time(pattern: .hourMinuteSecond))
    }

    private var startDate: String {
        process.startDate?.formatted(date: .abbreviated, time: .standard) ?? "Unavailable"
    }
}
