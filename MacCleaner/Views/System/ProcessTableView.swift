import SwiftUI

struct ProcessTableView: View {
    @ObservedObject var viewModel: SystemViewModel
    @FocusState.Binding var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            tableContent
        }
        .onDeleteCommand {
            viewModel.requestTerminateSelected()
        }
    }

    // MARK: - Header: search + status

    private var headerRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search processes…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if viewModel.isSearching {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
            )
            .frame(width: 260)

            Spacer()

            if let updated = viewModel.lastUpdated {
                Text("Updated \(updated, style: .time)")
                    .font(.caption)
                    .foregroundColor(.tertiary)
                    .monospacedDigit()
            }
            Text("\(viewModel.visibleProcesses.count) processes")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Table / empty states

    @ViewBuilder
    private var tableContent: some View {
        if viewModel.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading system information…")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.processes.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("Unable to retrieve process information.")
                    .font(.headline)
                Text("Check application permissions and try again.")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.visibleProcesses.isEmpty {
            VStack(spacing: 8) {
                Text("No processes match \"\(viewModel.searchText)\".")
                    .font(.headline)
                Text("Try a different name, PID, path, or user.")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            processTable
        }
    }

    // Split into groups: one TableColumnBuilder with all nine columns makes the
    // type checker time out, so each group is checked independently.
    @TableColumnBuilder<ProcessSnapshot>
    private var identityColumns: some TableColumnContent<ProcessSnapshot> {
        TableColumn("Process", value: \.name) { process in
            HStack(spacing: 6) {
                if process.isSelf {
                    Image(systemName: "app.badge.checkmark")
                        .foregroundColor(.secondary)
                        .help("This is MacCleaner itself")
                } else if !process.canTerminate {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                        .help("Protected process — termination is disabled")
                }
                Text(process.name)
                    .lineLimit(1)
            }
        }
        .width(min: 140, ideal: 200)

        TableColumn("PID", value: \.pid) { process in
            Text(String(process.pid))
                .monospacedDigit()
        }
        .width(70)

        TableColumn("CPU %", value: \.cpuPercent) { process in
            Text(FormatUtils.percent(process.cpuPercent))
                .monospacedDigit()
        }
        .width(70)
    }

    @TableColumnBuilder<ProcessSnapshot>
    private var resourceColumns: some TableColumnContent<ProcessSnapshot> {
        TableColumn("Memory", value: \.memoryBytes) { process in
            Text(FormatUtils.byteCount(process.memoryBytes))
                .monospacedDigit()
        }
        .width(90)

        TableColumn("Mem %", value: \.memoryPercent) { process in
            Text(FormatUtils.percent(process.memoryPercent))
                .monospacedDigit()
        }
        .width(70)

        TableColumn("Status", value: \.status.rawValue) { process in
            Text(process.status.rawValue)
                .foregroundColor(process.status == .zombie ? .red : .primary)
        }
        .width(90)
    }

    @TableColumnBuilder<ProcessSnapshot>
    private var detailColumns: some TableColumnContent<ProcessSnapshot> {
        TableColumn("User", value: \.username) { process in
            Text(process.username ?? FormatUtils.unavailable)
                .foregroundColor(process.username == nil ? .tertiary : .primary)
        }
        .width(110)

        TableColumn("Path", value: \.executablePath) { process in
            Text(process.executablePath ?? FormatUtils.unavailable)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(process.executablePath ?? "Path unavailable")
        }

        TableColumn("Actions") { process in
            Menu {
                Button("View Details") { viewModel.select(pid: process.pid) }
                Divider()
                Button("Terminate…", role: .destructive) {
                    viewModel.requestTerminate(process, force: false)
                }
                .disabled(!process.canTerminate)
                Button("Force Kill…", role: .destructive) {
                    viewModel.requestTerminate(process, force: true)
                }
                .disabled(!process.canTerminate)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help(terminationHelp(for: process))
            .frame(width: 30)
        }
        .width(44)
    }

    private var processTable: some View {
        Table(viewModel.visibleProcesses, selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
            identityColumns
            resourceColumns
            detailColumns
        }
        .contextMenu(forSelectionType: ProcessSnapshot.ID.self) { ids in
            if let pid = ids.first, let process = viewModel.process(pid: pid) {
                contextMenuItems(for: process)
            }
        }
        .onChange(of: viewModel.selection) { _ in
            viewModel.selectionChanged()
        }
        .tableStyle(.inset)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenuItems(for process: ProcessSnapshot) -> some View {
        Button("View Details") { viewModel.select(pid: process.pid) }
        Divider()
        Button("Copy PID") { viewModel.copyToClipboard(String(process.pid)) }
        Button("Copy Process Name") { viewModel.copyToClipboard(process.name) }
        Button("Copy Executable Path") {
            if let path = process.executablePath { viewModel.copyToClipboard(path) }
        }
        .disabled(process.executablePath == nil)
        Button("Open File Location") { viewModel.openFileLocation(for: process) }
            .disabled(process.executablePath == nil)
        Divider()
        Button("Terminate…", role: .destructive) {
            viewModel.requestTerminate(process, force: false)
        }
        .disabled(!process.canTerminate)
        Button("Force Kill…", role: .destructive) {
            viewModel.requestTerminate(process, force: true)
        }
        .disabled(!process.canTerminate)
    }

    private func terminationHelp(for process: ProcessSnapshot) -> String {
        if process.isSelf { return "MacCleaner cannot terminate itself" }
        if !process.canTerminate { return "Protected process — termination is disabled" }
        return "Terminate or force-kill this process"
    }
}
