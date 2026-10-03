import Foundation

/// Lifecycle state of a process, derived from the kernel process state.
enum ProcessStatus: String, CaseIterable {
    case running = "Running"
    case sleeping = "Sleeping"
    case stopped = "Stopped"
    case zombie = "Zombie"
    case idle = "Idle"
    case unknown = "Unknown"
}

/// A point-in-time view of a single process.
///
/// Fields the OS cannot provide are `nil` — never fabricated — and the UI
/// renders them as "Unavailable" rather than a misleading zero.
struct ProcessSnapshot: Identifiable, Hashable {
    let pid: pid_t
    let parentPid: pid_t
    let name: String
    let executablePath: String?
    let username: String?
    let uid: uid_t
    let status: ProcessStatus
    /// Percent of a single CPU core's capacity used over the last sample interval.
    /// `nil` until two samples exist. May exceed 100 for multi-threaded processes
    /// (100% = one fully-used core).
    let cpuPercent: Double?
    /// Resident memory in bytes.
    let memoryBytes: UInt64
    /// Percent of total physical RAM. `nil` when total RAM is unknown.
    let memoryPercent: Double?
    let startDate: Date?
    let threadCount: Int?
    /// True for processes owned by root or the kernel.
    let isSystemProcess: Bool
    /// Whether the current user may attempt termination (disabled for PID 0/1,
    /// the app itself, and processes owned by other users when not root).
    let canTerminate: Bool
    /// Whether this snapshot is the MacCleaner app itself.
    let isSelf: Bool

    var id: pid_t { pid }
}
