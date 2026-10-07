import AppKit
import Darwin
import Foundation

/// macOS implementation of ``SystemMonitor`` using only native OS APIs —
/// no shelling out, no mock data.
///
/// Data sources:
/// - Process enumeration: `sysctl([CTL_KERN, KERN_PROC, KERN_PROC_ALL])`
/// - Per-process memory/threads/CPU time: `proc_pidinfo(PROC_PIDTASKINFO)`
/// - Process names: `proc_pidinfo(PROC_PIDTBSDINFO)` (up to 32 chars),
///   falling back to `kinfo_proc.p_comm`
/// - Executable paths: `proc_pidpath`
/// - Command lines: `sysctl(KERN_PROCARGS2)`
/// - System memory: `host_statistics64(HOST_VM_INFO64)` + `sysctl(hw.memsize)`
/// - Swap: `sysctl(vm.swapusage)`
/// - Overall CPU: `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` deltas
/// - Termination: `NSRunningApplication.terminate()` for GUI apps (graceful),
///   otherwise `kill(pid, SIGTERM)`; `kill(pid, SIGKILL)` to force.
///
/// Per-process CPU % is computed from `pti_total_user`/`pti_total_system`
/// deltas. Per XNU's `fill_taskinfo`, these counters are in **nanoseconds**;
/// the percentage is `(deltaNs / wallNs) * 100`, so 100% = one fully-used
/// core and multithreaded processes may exceed 100, matching Activity Monitor.
final class MacOSSystemMonitor: SystemMonitor, @unchecked Sendable {

    // MARK: - Delta state (previous sample)

    private struct CpuSample {
        let user: UInt64
        let system: UInt64
    }

    private var previousCpuTimes: [pid_t: CpuSample] = [:]
    private var previousSampleDate: Date?
    private var previousCpuLoad: (total: UInt64, idle: UInt64)?
    private let stateLock = NSLock()

    // MARK: - SystemMonitor

    func sampleSystem() -> SystemSnapshot {
        let now = Date()
        let totalRAM = Self.totalPhysicalMemory()
        let ownPid = getpid()
        let currentUid = getuid()

        stateLock.lock()
        let prevTimes = previousCpuTimes
        let prevDate = previousSampleDate
        stateLock.unlock()
        let wallSeconds = prevDate.map { now.timeIntervalSince($0) } ?? 0

        var snapshots: [ProcessSnapshot] = []
        var cpuTimes: [pid_t: CpuSample] = [:]
        var usernameCache: [uid_t: String] = [:]
        var unknownUids: Set<uid_t> = []
        let coreCount = max(1, ProcessInfo.processInfo.processorCount)

        let kprocs = Self.enumerateProcesses()
        snapshots.reserveCapacity(kprocs.count)
        cpuTimes.reserveCapacity(kprocs.count)

        for kp in kprocs {
            let pid = kp.kp_proc.p_pid
            guard pid > 0 else { continue }

            let uid = kp.kp_eproc.e_ucred.cr_uid
            let username: String? = {
                if let cached = usernameCache[uid] { return cached }
                if unknownUids.contains(uid) { return nil }
                if let name = Self.username(for: uid) {
                    usernameCache[uid] = name
                    return name
                }
                unknownUids.insert(uid)
                return nil
            }()

            let task = Self.taskInfo(pid: pid)
            let memoryBytes = task?.pti_resident_size ?? 0

            var cpuPercent: Double? = nil
            if let task {
                let sample = CpuSample(user: task.pti_total_user, system: task.pti_total_system)
                cpuTimes[pid] = sample
                if let prev = prevTimes[pid], wallSeconds > 0 {
                    // Wrapping subtract: a counter reset yields a huge delta, clamped below.
                    let deltaNs = (sample.user &- prev.user) &+ (sample.system &- prev.system)
                    let raw = Double(deltaNs) / (wallSeconds * 1_000_000_000) * 100
                    cpuPercent = min(max(raw, 0), Double(coreCount) * 100)
                }
            }

            let path = Self.executablePath(pid: pid)
            let isSelf = pid == ownPid
            let isSystem = uid == 0

            snapshots.append(ProcessSnapshot(
                pid: pid,
                parentPid: kp.kp_eproc.e_ppid,
                name: Self.bsdName(pid: pid) ?? Self.commName(from: kp),
                executablePath: path,
                username: username,
                uid: uid,
                status: Self.status(for: Int32(kp.kp_proc.p_stat)), // p_stat is CChar (Int8) in the SDK
                cpuPercent: cpuPercent,
                memoryBytes: memoryBytes,
                memoryPercent: totalRAM > 0 ? Double(memoryBytes) / Double(totalRAM) * 100 : nil,
                startDate: Self.startDate(from: kp.kp_proc.p_starttime),
                threadCount: task.map { Int($0.pti_threadnum) },
                isSystemProcess: isSystem,
                canTerminate: pid > 1 && !isSelf && (uid == currentUid || currentUid == 0),
                isSelf: isSelf
            ))
        }

        stateLock.lock()
        previousCpuTimes = cpuTimes
        previousSampleDate = now
        stateLock.unlock()

        let appCount = snapshots.filter { $0.executablePath?.contains(".app/Contents/MacOS/") == true }.count

        return SystemSnapshot(
            memory: Self.memoryInfo(totalBytes: totalRAM),
            cpu: CPUInfo(
                overallPercent: sampleOverallCPU(),
                logicalCores: coreCount,
                physicalCores: Self.sysctlInt("hw.physicalcpu"),
                frequencyHz: Self.sysctlUInt64("hw.cpufrequency").flatMap { $0 > 0 ? $0 : nil }
            ),
            processes: snapshots,
            applicationCount: appCount,
            timestamp: now
        )
    }

    func processDetails(pid: pid_t) throws -> ProcessDetails {
        try Self.validatePid(pid)
        // A fresh sample keeps parent/child relationships consistent with the table.
        let snapshot = sampleSystem()
        guard let target = snapshot.processes.first(where: { $0.pid == pid }) else {
            throw MonitorError.processNotFound(pid)
        }
        return ProcessDetails(
            snapshot: target,
            parent: snapshot.processes.first(where: { $0.pid == target.parentPid }),
            children: snapshot.processes
                .filter { $0.parentPid == pid }
                .sorted { $0.memoryBytes > $1.memoryBytes },
            commandLine: Self.commandLine(pid: pid),
            architecture: Self.architecture(pid: pid),
            priority: Self.niceValue(pid: pid)
        )
    }

    func terminate(pid: pid_t) throws {
        try Self.validatePid(pid)
        guard pid != getpid() else { throw MonitorError.cannotTerminateSelf }
        guard Self.processExists(pid) else { throw MonitorError.processNotFound(pid) }

        // Prefer AppKit's graceful quit for GUI apps (lets them prompt to save).
        // NSRunningApplication is main-thread bound, so hop there if needed.
        let gracefullyRequested: Bool = {
            if Thread.isMainThread {
                return NSRunningApplication(processIdentifier: pid)?.terminate() ?? false
            }
            return DispatchQueue.main.sync {
                NSRunningApplication(processIdentifier: pid)?.terminate() ?? false
            }
        }()
        if gracefullyRequested { return } // Delivered; caller verifies exit.

        if kill(pid, SIGTERM) != 0 {
            throw Self.errnoError(pid: pid, operation: "terminate")
        }
    }

    func forceKill(pid: pid_t) throws {
        try Self.validatePid(pid)
        guard pid != getpid() else { throw MonitorError.cannotTerminateSelf }
        guard Self.processExists(pid) else { throw MonitorError.processNotFound(pid) }
        if kill(pid, SIGKILL) != 0 {
            throw Self.errnoError(pid: pid, operation: "force kill")
        }
    }

    func openFileLocation(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw MonitorError.pathUnavailable
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - Overall CPU (delta of host_processor_info)

    private func sampleOverallCPU() -> Double? {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                 &cpuCount, &cpuInfo, &infoCount) == KERN_SUCCESS,
              let cpuInfo else { return nil }
        defer {
            let bytes = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), bytes)
        }

        var total: UInt64 = 0
        var idle: UInt64 = 0
        cpuInfo.withMemoryRebound(to: processor_cpu_load_info_data_t.self,
                                 capacity: Int(cpuCount)) { ptr in
            for i in 0..<Int(cpuCount) {
                let ticks = ptr[i].cpu_ticks
                total &+= UInt64(ticks.0) &+ UInt64(ticks.1) &+ UInt64(ticks.2) &+ UInt64(ticks.3)
                idle &+= UInt64(ticks.3)
            }
        }

        stateLock.lock()
        defer { stateLock.unlock() }
        let previous = previousCpuLoad
        previousCpuLoad = (total, idle)
        guard let previous, total > previous.total else { return nil } // first sample
        let totalDelta = total - previous.total
        let idleDelta = idle >= previous.idle ? idle - previous.idle : 0
        guard totalDelta > 0 else { return nil }
        return Double(totalDelta - idleDelta) / Double(totalDelta) * 100
    }

    // MARK: - Native helpers

    static func validatePid(_ pid: pid_t) throws {
        guard pid > 0 else { throw MonitorError.invalidPid(pid) }
    }

    static func processExists(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM // exists, but we may not signal it
    }

    static func errnoError(pid: pid_t, operation: String) -> MonitorError {
        switch errno {
        case ESRCH:
            return .processNotFound(pid)
        case EPERM:
            return .accessDenied(
                "Unable to \(operation) this process. It requires elevated privileges or is protected by the operating system."
            )
        default:
            return .terminationFailed(
                "The operating system reported an error while trying to \(operation) process \(pid) (errno \(errno))."
            )
        }
    }

    static func enumerateProcesses() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        guard count > 0 else { return [] }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        var actualSize = size
        let result = procs.withUnsafeMutableBufferPointer { buffer in
            sysctl(&mib, 4, buffer.baseAddress, &actualSize, nil, 0)
        }
        guard result == 0 else { return [] }
        return Array(procs.prefix(actualSize / MemoryLayout<kinfo_proc>.stride))
    }

    /// Up-to-32-char name from PROC_PIDTBSDINFO; more complete than p_comm.
    static func bsdName(pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let expected = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected) == expected else { return nil }
        var copy = info
        return withUnsafePointer(to: &copy.pbi_name) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: 32) { ptr in
                let name = String(cString: ptr)
                return name.isEmpty ? nil : name
            }
        }
    }

    /// 16-char kernel comm name fallback.
    static func commName(from kp: kinfo_proc) -> String {
        var kp = kp
        return withUnsafePointer(to: &kp.kp_proc.p_comm) { raw in
            raw.withMemoryRebound(to: CChar.self, capacity: 17) { ptr in
                String(cString: ptr)
            }
        }
    }

    static func taskInfo(pid: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let expected = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, expected) == expected else { return nil }
        return info
    }

    static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = buffer.withUnsafeMutableBufferPointer { ptr in
            proc_pidpath(pid, ptr.baseAddress, UInt32(MAXPATHLEN))
        }
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    static func username(for uid: uid_t) -> String? {
        guard let pw = getpwuid(uid) else { return nil }
        return String(cString: pw.pointee.pw_name)
    }

    static func status(for pStat: Int32) -> ProcessStatus {
        switch pStat {
        case SIDL: return .idle
        case SRUN: return .running
        case SSLEEP: return .sleeping
        case SSTOP: return .stopped
        case SZOMB: return .zombie
        default: return .unknown
        }
    }

    static func startDate(from tv: timeval) -> Date? {
        guard tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    static func totalPhysicalMemory() -> UInt64 {
        sysctlUInt64("hw.memsize") ?? 0
    }

    static func memoryInfo(totalBytes: UInt64) -> MemoryInfo {
        let pageSize = UInt64(vm_kernel_page_size)
        var usedBytes: UInt64?
        var vmStat = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr: kern_return_t = withUnsafeMutablePointer(to: &vmStat) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        if kr == KERN_SUCCESS {
            // "Used" matches Activity Monitor's definition: wired + app + compressed.
            // Free + speculative pages count as available.
            usedBytes = (UInt64(vmStat.wire_count) + UInt64(vmStat.active_count)
                + UInt64(vmStat.inactive_count) + UInt64(vmStat.speculative_count)
                + UInt64(vmStat.compressor_page_count)) * pageSize
        }

        var swapUsed: UInt64?
        var swapTotal: UInt64?
        var sw = xsw_usage()
        var swSize = MemoryLayout<xsw_usage>.size
        if "vm.swapusage".withCString({ sysctlbyname($0, &sw, &swSize, nil, 0) }) == 0 {
            swapUsed = sw.xsu_used
            swapTotal = sw.xsu_total
        }

        return MemoryInfo(
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal
        )
    }

    /// Full command line via KERN_PROCARGS2. Returns nil when the OS
    /// withholds it (permissions) or the process exits mid-read.
    static func commandLine(pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid, 0]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0,
              size > 0, size <= 4 * 1024 * 1024 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        var actualSize = size
        let ok: Int32 = buffer.withUnsafeMutableBufferPointer { ptr in
            sysctl(&mib, 3, ptr.baseAddress, &actualSize, nil, 0)
        }
        guard ok == 0, actualSize >= 4 else { return nil }

        let argc: Int32 = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0, argc < 10_000 else { return nil }

        // Layout: argc (4 bytes), exec-path string, then argc argv strings, then env.
        var offset = 4
        while offset < actualSize && buffer[offset] != 0 { offset += 1 }
        offset += 1 // skip the null terminator

        var args: [String] = []
        args.reserveCapacity(Int(argc))
        var current = [UInt8]()
        var parsed = 0
        while offset < actualSize && parsed < argc {
            let byte = buffer[offset]
            offset += 1
            if byte == 0 {
                args.append(String(bytes: current, encoding: .utf8) ?? "")
                current.removeAll(keepingCapacity: true)
                parsed += 1
            } else {
                current.append(byte)
            }
        }
        guard args.count == argc else { return nil } // truncated buffer
        return args.joined(separator: " ")
    }

    static func architecture(pid: pid_t) -> String? {
        // proc_archinfo / PROC_PIDARCHINFO are not exposed to Swift by the SDK,
        // so use the sysctl.proc_cputype node instead: it takes the target pid
        // as the "new" buffer and returns the process's cpu_type as an Int32.
        var cputype: Int32 = 0
        var len = MemoryLayout<Int32>.size
        var target = pid
        let ok = "sysctl.proc_cputype".withCString { name in
            sysctlbyname(name, &cputype, &len, &target, MemoryLayout<pid_t>.size)
        }
        guard ok == 0 else { return nil }
        switch cputype {
        case CPU_TYPE_ARM64: return "arm64"
        case CPU_TYPE_X86_64: return "x86_64"
        case CPU_TYPE_ARM: return "arm"
        case CPU_TYPE_I386: return "i386"
        default: return nil
        }
    }

    static func niceValue(pid: pid_t) -> Int? {
        errno = 0
        let value = getpriority(PRIO_PROCESS, UInt32(pid))
        if value == -1 && errno != 0 { return nil }
        return Int(value)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        let ok = name.withCString { sysctlbyname($0, &value, &size, nil, 0) }
        return ok == 0 ? value : nil
    }

    static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        let ok = name.withCString { sysctlbyname($0, &value, &size, nil, 0) }
        return ok == 0 ? value : nil
    }
}
