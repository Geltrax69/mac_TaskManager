import Foundation

/// Errors from process inspection and management. Every case carries a
/// user-facing message — the UI never shows raw errnos.
enum MonitorError: LocalizedError {
    case invalidPid(pid_t)
    case processNotFound(pid_t)
    case cannotTerminateSelf
    case accessDenied(String)
    case terminationFailed(String)
    case pathUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidPid(let pid):
            return "\"\(pid)\" is not a valid process identifier."
        case .processNotFound(let pid):
            return "Process \(pid) no longer exists. It may have exited before the action completed."
        case .cannotTerminateSelf:
            return "MacCleaner cannot terminate itself."
        case .accessDenied(let reason):
            return reason
        case .terminationFailed(let reason):
            return reason
        case .pathUnavailable:
            return "The executable path is unavailable. The process may have exited or the operating system may not expose it."
        }
    }
}

/// Full detail record for one process, assembled on demand (not in the hot
/// refresh loop) since some fields require extra syscalls.
struct ProcessDetails {
    let snapshot: ProcessSnapshot
    let parent: ProcessSnapshot?
    let children: [ProcessSnapshot]
    /// Full command line, when the OS permits reading it.
    let commandLine: String?
    /// e.g. "arm64", "x86_64". `nil` when the OS doesn't report it.
    let architecture: String?
    /// Unix nice value. `nil` when unreadable.
    let priority: Int?
}

/// OS abstraction layer for process and resource inspection.
///
/// Each supported OS provides its own implementation using native APIs
/// (macOS: sysctl/libproc/Mach; never shelling out, never mock data).
/// The UI only ever talks to this protocol.
protocol SystemMonitor: AnyObject, Sendable {
    /// One full sample: memory, CPU, and every running process.
    /// Best-effort and non-throwing — partial data is returned rather than
    /// failing the whole refresh because one process disappeared.
    func sampleSystem() -> SystemSnapshot

    /// On-demand detail for a single process.
    /// - Throws: `MonitorError` (.invalidPid, .processNotFound).
    func processDetails(pid: pid_t) throws -> ProcessDetails

    /// Graceful termination: asks a GUI app to quit via AppKit, otherwise
    /// sends SIGTERM. Returns once the request is *delivered*; the caller
    /// must verify the process actually exited before reporting success.
    /// - Throws: `MonitorError`.
    func terminate(pid: pid_t) throws

    /// Immediate termination via SIGKILL. Same delivery-then-verify contract.
    /// - Throws: `MonitorError`.
    func forceKill(pid: pid_t) throws

    /// Reveals the executable in Finder. The caller must have a valid path.
    /// - Throws: `MonitorError.pathUnavailable`.
    func openFileLocation(path: String) throws
}
