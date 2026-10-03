# MacCleaner

A native macOS utility app. Its flagship feature is a **System tab** — a Task
Manager / Activity Monitor-style process and resource manager built directly
into the app using only native macOS APIs. No shelling out, no mock data.

## Features

**Resource dashboard** (auto-refreshing)
- RAM: total / used / available / usage %, with a visual meter; swap reported separately, never mixed into physical RAM
- CPU: overall utilization, logical + physical core counts, frequency when the OS reports it (Apple Silicon reports 0 → shown as "—")
- Processes: total running, applications (`.app` bundles) vs background

**Process table**
- Columns: Process, PID, CPU %, Memory, Mem %, Status, User, Path, Actions
- Native sorting (default: memory descending), instant search across name / PID / path / user (⌘F)
- Top-5 memory consumers strip — tapping one selects it in the table
- Per-row `⋮` menu and full right-click context menu: View Details, Copy PID / Name / Path, Open File Location, Terminate…, Force Kill…
- Refresh controls: manual (⌘R), auto-refresh toggle, 0.5 / 1 / 2 / 5 s intervals
- Loading, empty, and no-match states

**Process details inspector**
- Name, PID, parent PID, CPU, memory, status, user, start time, thread count, nice value, architecture, executable path, command line, parent + children (clickable)

**Safe termination**
- Graceful quit via `NSRunningApplication.terminate()` for GUI apps, `SIGTERM` otherwise; `SIGKILL` for force kill
- Confirmation dialogs before anything destructive
- Success is only reported after the OS confirms the process exited (`kill(pid, 0)` polling)
- Protected processes (PID 0/1, other users' processes, MacCleaner itself) can't be terminated from the UI; permission failures explain themselves

## Architecture

```
MacCleaner/
├── App/            # MacCleanerApp, ContentView (Clean + System tabs)
├── Models/         # ProcessSnapshot, MemoryInfo, CPUInfo, SystemSnapshot
├── Services/
│   ├── SystemMonitor.swift      # OS abstraction protocol + MonitorError
│   ├── MacOSSystemMonitor.swift # macOS implementation (sysctl/libproc/Mach)
│   └── FormatUtils.swift        # ByteCountFormatter / percent helpers
├── ViewModels/     # SystemViewModel (refresh loop, selection, termination flow)
├── Views/
│   ├── CleanTabView.swift
│   └── System/     # Tab, cards, table, inspector, top-memory strip
└── Resources/
MacCleanerTests/    # XCTest: formatting, search/sort, validation, memory math
```

The `SystemMonitor` protocol is the seam for other platforms:
`WindowsProcessManager` / `LinuxProcessManager` would slot in behind the same
interface (`sampleSystem`, `processDetails`, `terminate`, `forceKill`,
`openFileLocation`).

Native APIs used on macOS: `sysctl(KERN_PROC)` process enumeration,
`proc_pidinfo(PROC_PIDTASKINFO / PROC_PIDTBSDINFO / PROC_PIDARCHINFO)`,
`proc_pidpath`, `KERN_PROCARGS2` command lines, `host_statistics64` memory,
`host_processor_info` CPU load, `vm.swapusage`, `kill(2)`.

Per-process CPU % is derived from `pti_total_user`/`pti_total_system` deltas
(nanoseconds, per XNU's `fill_taskinfo`): 100% = one fully-used core, so
multithreaded processes can exceed 100%, matching Activity Monitor.

## Build

Requires macOS with Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open MacCleaner.xcodeproj
```

Then build & run (⌘R). Tests: ⌘U, or `xcodebuild -scheme MacCleaner -destination 'platform=macOS' test`.
CI (`.github/workflows/ci.yml`) builds and tests on every push.

## Verification status

The code is written against the macOS 13+ SDK but **has not been compiled** —
this development environment is Linux with no Swift toolchain. Before release,
build on a Mac and confirm:

1. It compiles cleanly (`xcodegen generate`, then build).
2. Tests pass (`⌘U`).
3. The System tab shows real processes with plausible CPU/RAM values after two refresh intervals (per-process CPU needs two samples; the first shows "—").
4. Terminate / force kill work on a sacrificial process (e.g. `sleep 1000` in Terminal) with confirmation dialogs.
5. Protected processes (e.g. PID 1) show as locked with termination disabled.
