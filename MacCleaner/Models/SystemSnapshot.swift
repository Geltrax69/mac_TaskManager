import Foundation

/// Physical memory statistics. `nil` values mean the OS call failed —
/// the UI must render "—", never a fabricated zero.
struct MemoryInfo {
    /// Total physical RAM in bytes. 0 when unknown.
    let totalBytes: UInt64
    /// Currently used physical RAM in bytes.
    let usedBytes: UInt64?
    /// Swap/pagefile currently in use, when the OS reports it.
    let swapUsedBytes: UInt64?
    /// Total swap/pagefile, when the OS reports it.
    let swapTotalBytes: UInt64?

    var availableBytes: UInt64? {
        guard let used = usedBytes, totalBytes >= used else { return nil }
        return totalBytes - used
    }

    var usagePercent: Double? {
        guard totalBytes > 0, let used = usedBytes else { return nil }
        return Double(used) / Double(totalBytes) * 100
    }
}

struct CPUInfo {
    /// Overall utilization across all cores, 0–100. `nil` until two samples exist.
    let overallPercent: Double?
    let logicalCores: Int
    let physicalCores: Int?
    /// Current frequency in Hz. `nil` when the OS doesn't report it
    /// (e.g. Apple Silicon reports 0 via hw.cpufrequency).
    let frequencyHz: UInt64?
}

struct SystemSnapshot {
    let memory: MemoryInfo
    let cpu: CPUInfo
    let processes: [ProcessSnapshot]
    /// Processes that are GUI applications (executable inside an .app bundle).
    let applicationCount: Int
    let timestamp: Date

    var totalCount: Int { processes.count }
    var backgroundCount: Int { totalCount - applicationCount }
}
