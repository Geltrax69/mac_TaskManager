import SwiftUI

struct SystemTabView: View {
    @StateObject private var viewModel = SystemViewModel(monitor: MacOSSystemMonitor())
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ResourceCardsView(snapshot: viewModel.snapshot)
                TopMemoryView(processes: viewModel.topMemoryProcesses) { pid in
                    viewModel.select(pid: pid)
                }
            }
            .padding(12)

            Divider()

            HSplitView {
                ProcessTableView(viewModel: viewModel, searchFocused: $searchFocused)
                    .frame(minWidth: 520)

                if viewModel.selectedProcess != nil {
                    Group {
                        if let details = viewModel.selectedDetails {
                            ProcessDetailView(
                                details: details,
                                onSelectPid: { viewModel.select(pid: $0) },
                                onTerminate: { viewModel.requestTerminate($0, force: $1) },
                                onCopy: { viewModel.copyToClipboard($0) },
                                onOpenLocation: { viewModel.openFileLocation(for: $0) },
                                onClose: { viewModel.selection = [] }
                            )
                        } else {
                            VStack {
                                ProgressView()
                                Text("Loading details…")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh process information now (⌘R)")
            }
            ToolbarItem {
                Toggle("Auto-refresh", isOn: $viewModel.autoRefresh)
                    .toggleStyle(.switch)
                    .help("Automatically refresh process information")
            }
            ToolbarItem {
                Picker("Interval", selection: $viewModel.refreshInterval) {
                    Text("0.5 s").tag(0.5 as TimeInterval)
                    Text("1 s").tag(1.0 as TimeInterval)
                    Text("2 s").tag(2.0 as TimeInterval)
                    Text("5 s").tag(5.0 as TimeInterval)
                }
                .pickerStyle(.menu)
                .disabled(!viewModel.autoRefresh)
                .help("Auto-refresh interval")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusProcessSearch)) { _ in
            searchFocused = true
        }
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        // Terminate / force-kill confirmation (spec copy).
        .alert(
            "Terminate Process?",
            isPresented: terminateAlertPresented,
            presenting: viewModel.pendingTermination
        ) { pending in
            Button("Cancel", role: .cancel) {
                viewModel.pendingTermination = nil
            }
            Button(pending.force ? "Force Kill" : "Terminate", role: .destructive) {
                viewModel.confirmPendingTermination()
            }
            .keyboardShortcut(.defaultAction)
        } message: { pending in
            if pending.force {
                Text("This immediately stops the process and may cause unsaved data to be lost.")
            } else {
                Text("\(pending.process.name) (PID \(pending.process.pid)) is currently using \(FormatUtils.byteCount(pending.process.memoryBytes)) of RAM.\n\nAre you sure you want to terminate this process?")
            }
        }
        // Operation failures: permission, process vanished, etc.
        // Note: the presenting: overload needs Identifiable data, which String
        // isn't — so this uses the plain isPresented form and reads the
        // message from the view model inside the message closure.
        .alert(
            "Unable to complete action",
            isPresented: actionErrorPresented
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.actionErrorMessage ?? "")
        }
    }

    private var terminateAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingTermination != nil },
            set: { if !$0 { viewModel.pendingTermination = nil } }
        )
    }

    private var actionErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.actionErrorMessage != nil },
            set: { if !$0 { viewModel.actionErrorMessage = nil } }
        )
    }
}
