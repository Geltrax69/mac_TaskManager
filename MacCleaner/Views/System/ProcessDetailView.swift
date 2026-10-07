import SwiftUI

/// Inspector-style panel for the selected process.
struct ProcessDetailView: View {
    let details: ProcessDetails
    var onSelectPid: (pid_t) -> Void
    var onTerminate: (ProcessSnapshot, Bool) -> Void
    var onCopy: (String) -> Void
    var onOpenLocation: (ProcessSnapshot) -> Void
    var onClose: () -> Void

    private var process: ProcessSnapshot { details.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                overviewSection
                resourcesSection
                executableSection
                hierarchySection
                actionsSection
            }
            .padding(14)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("PID \(process.pid)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if !process.canTerminate {
                Label("Protected", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help(protectedReason)
            }
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close details (Esc)")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var protectedReason: String {
        if process.isSelf { return "This is MacCleaner itself." }
        if process.pid <= 1 { return "A core system process. Termination is disabled." }
        return "Owned by another user or protected by the OS."
    }

    // MARK: - Sections

    private var overviewSection: some View {
        section("Overview") {
            DetailRow(label: "Status", value: process.status.rawValue)
            DetailRow(label: "User", value: process.username ?? FormatUtils.unavailable)
            DetailRow(label: "Parent PID", value: parentLabel)
            DetailRow(label: "Started", value: startedLabel)
        }
    }

    private var resourcesSection: some View {
        section("Resources") {
            DetailRow(label: "CPU", value: FormatUtils.percent(process.cpuPercent),
                      help: "Percent of one CPU core over the last sample. Can exceed 100%.")
            DetailRow(label: "Memory", value: FormatUtils.byteCount(process.memoryBytes))
            DetailRow(label: "Memory %", value: FormatUtils.percent(process.memoryPercent),
                      help: "Share of total physical RAM.")
            DetailRow(label: "Threads", value: process.threadCount.map(String.init) ?? FormatUtils.unavailable)
            DetailRow(label: "Nice", value: details.priority.map(String.init) ?? FormatUtils.unavailable,
                      help: "Unix scheduling priority (nice value).")
            DetailRow(label: "Architecture", value: details.architecture ?? FormatUtils.unavailable)
        }
    }

    private var executableSection: some View {
        section("Executable") {
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Path", value: process.executablePath ?? FormatUtils.unavailable)
                    .contextMenu {
                        if let path = process.executablePath {
                            Button("Copy Path") { onCopy(path) }
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Command Line")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let commandLine = details.commandLine, !commandLine.isEmpty {
                        Text(commandLine)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                    } else {
                        Text("Unavailable — the OS did not expose it.")
                            .font(.caption)
                            .foregroundColor(.tertiaryLabel)
                    }
                }
            }
        }
    }

    private var hierarchySection: some View {
        section("Hierarchy") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Parent")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let parent = details.parent {
                    processLink(parent)
                } else {
                    Text("Unavailable").font(.caption).foregroundColor(.tertiaryLabel)
                }
                Text("Children (\(details.children.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                if details.children.isEmpty {
                    Text("None").font(.caption).foregroundColor(.tertiaryLabel)
                } else {
                    ForEach(details.children.prefix(20)) { child in
                        processLink(child)
                    }
                    if details.children.count > 20 {
                        Text("…and \(details.children.count - 20) more")
                            .font(.caption)
                            .foregroundColor(.tertiaryLabel)
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 8) {
            Button("Terminate…") { onTerminate(process, false) }
                .disabled(!process.canTerminate)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button("Force Kill…") { onTerminate(process, true) }
                .disabled(!process.canTerminate)
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            if !process.canTerminate {
                Text(protectedReason)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundColor(.secondary)
            content()
        }
    }

    private func processLink(_ process: ProcessSnapshot) -> some View {
        Button {
            onSelectPid(process.pid)
        } label: {
            HStack {
                Text(process.name).lineLimit(1)
                Spacer()
                Text("PID \(process.pid)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Select \(process.name) (PID \(process.pid))")
    }

    private var parentLabel: String {
        if let parent = details.parent {
            return "\(parent.name) (\(parent.pid))"
        }
        return "PID \(process.parentPid)"
    }

    private var startedLabel: String {
        guard let date = process.startDate else { return FormatUtils.unavailable }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var help: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 92, alignment: .trailing)
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(help ?? "")
    }
}
