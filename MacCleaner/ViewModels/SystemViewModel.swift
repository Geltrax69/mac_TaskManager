import AppKit
import Darwin
import Foundation
import SwiftUI

/// Pending destructive action awaiting user confirmation.
struct PendingTermination: Identifiable {
    let process: ProcessSnapshot
    let force: Bool
    var id: pid_t { process.pid }
}

@MainActor
final class SystemViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var snapshot: SystemSnapshot?
    @Published private(set) var isLoading = true
    @Published private(set) var lastUpdated: Date?
    @Published var searchText = ""
    @Published var sortOrder = [KeyPathComparator(\ProcessSnapshot.memoryBytes, order: .reverse)]
    @Published var selection: Set<pid_t> = []
    @Published var autoRefresh = true {
        didSet { restartTimer() }
    }
    @Published var refreshInterval: TimeInterval = 2.0 {
        didSet { restartTimer() }
    }
    @Published private(set) var selectedDetails: ProcessDetails?
    @Published var pendingTermination: PendingTermination?
    @Published var actionErrorMessage: String?

    // MARK: - Dependencies

    private let monitor: any SystemMonitor
    private let workQueue = DispatchQueue(label: "com.geltrax.maccleaner.system", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var isRefreshing = false // only touched on workQueue

    init(monitor: any SystemMonitor) {
        self.monitor = monitor
    }

    // MARK: - Derived data

    var processes: [ProcessSnapshot] { snapshot?.processes ?? [] }

    var visibleProcesses: [ProcessSnapshot] {
        let base = processes
        let filtered: [ProcessSnapshot]
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = base
        } else {
            filtered = base.filter { Self.matches($0, query: searchText) }
        }
        return filtered.sorted(using: sortOrder)
    }

    var selectedProcess: ProcessSnapshot? {
        guard let pid = selection.first else { return nil }
        return processes.first { $0.pid == pid }
    }

    var topMemoryProcesses: [ProcessSnapshot] {
        processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5).map { $0 }
    }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func process(pid: pid_t) -> ProcessSnapshot? {
        processes.first { $0.pid == pid }
    }

    // MARK: - Refresh

    func start() {
        refresh()
        restartTimer()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func refresh() {
        workQueue.async { [weak self] in
            guard let self, !self.isRefreshing else { return } // never overlap refreshes
            self.isRefreshing = true
            defer { self.isRefreshing = false }
            let snap = self.monitor.sampleSystem()
            Task { @MainActor [weak self] in
                self?.snapshot = snap
                self?.isLoading = false
                self?.lastUpdated = snap.timestamp
            }
        }
    }

    private func restartTimer() {
        timer?.cancel()
        timer = nil
        guard autoRefresh else { return }
        let source = DispatchSource.makeTimerSource(queue: workQueue)
        source.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        source.setEventHandler { [weak self] in
            self?.refresh()
        }
        source.resume()
        timer = source
    }

    // MARK: - Selection & details

    func select(pid: pid_t) {
        selection = [pid]
        refreshDetails()
    }

    func selectionChanged() {
        refreshDetails()
    }

    private func refreshDetails() {
        guard let pid = selection.first else {
            selectedDetails = nil
            return
        }
        // Details need extra syscalls; fetch off the main thread.
        Task.detached(priority: .utility) { [monitor] in
            let details = try? monitor.processDetails(pid: pid)
            await MainActor.run { [weak self] in
                // Only apply if the selection hasn't moved on.
                if self?.selection.first == pid {
                    self?.selectedDetails = details
                }
            }
        }
    }

    // MARK: - Termination

    func requestTerminate(_ process: ProcessSnapshot, force: Bool) {
        pendingTermination = PendingTermination(process: process, force: force)
    }

    func requestTerminateSelected() {
        guard let process = selectedProcess, process.canTerminate else { return }
        requestTerminate(process, force: false)
    }

    func confirmPendingTermination() {
        guard let pending = pendingTermination else { return }
        pendingTermination = nil
        let pid = pending.process.pid
        Task.detached(priority: .userInitiated) { [monitor] in
            do {
                if pending.force {
                    try monitor.forceKill(pid: pid)
                } else {
                    try monitor.terminate(pid: pid)
                }
                // Never claim success until the OS confirms the process is gone.
                let exited = Self.waitForExit(pid: pid, timeout: 3.0)
                await MainActor.run { [weak self] in
                    if exited {
                        self?.selection.remove(pid)
                        self?.refresh()
                    } else {
                        self?.actionErrorMessage =
                            "The process is still running. It may be ignoring termination requests — try Force Kill."
                    }
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.actionErrorMessage = message
                }
            }
        }
    }

    /// Polls `kill(pid, 0)` until the process is gone or the timeout elapses.
    /// `kill(pid, 0)` succeeds for zombies too, so a reaped-but-unreaped
    /// process correctly reports as "still present".
    private static func waitForExit(pid: pid_t, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0, errno == ESRCH { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        if kill(pid, 0) != 0, errno == ESRCH { return true }
        return false
    }

    // MARK: - Clipboard

    func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func openFileLocation(for process: ProcessSnapshot) {
        guard let path = process.executablePath else {
            actionErrorMessage = MonitorError.pathUnavailable.errorDescription
            return
        }
        do {
            try monitor.openFileLocation(path: path)
        } catch {
            actionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Search & sort (pure logic, unit-tested)

    // Pure logic — safe to call off the main actor (unit-tested).
    nonisolated static func matches(_ process: ProcessSnapshot, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        if process.name.localizedCaseInsensitiveContains(q) { return true }
        if String(process.pid).contains(q) { return true }
        if let path = process.executablePath, path.localizedCaseInsensitiveContains(q) { return true }
        if let user = process.username, user.localizedCaseInsensitiveContains(q) { return true }
        return false
    }
}
