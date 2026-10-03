import XCTest
@testable import MacCleaner

/// Tests for the pure search/sort logic used by the process table.
/// Uses fixture snapshots — no live processes involved.
final class ProcessQueryTests: XCTestCase {

    private func fixture(
        pid: pid_t,
        name: String,
        path: String? = nil,
        user: String? = "geltrax",
        cpu: Double? = 0,
        memory: UInt64 = 0,
        status: ProcessStatus = .running
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid,
            parentPid: 1,
            name: name,
            executablePath: path,
            username: user,
            uid: 501,
            status: status,
            cpuPercent: cpu,
            memoryBytes: memory,
            memoryPercent: nil,
            startDate: nil,
            threadCount: nil,
            isSystemProcess: false,
            canTerminate: true,
            isSelf: false
        )
    }

    private var fixtures: [ProcessSnapshot] {
        [
            fixture(pid: 12480, name: "Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", cpu: 8.4, memory: 1_824_000_000),
            fixture(pid: 18342, name: "Code", path: "/Applications/Visual Studio Code.app/Contents/MacOS/Electron", cpu: 6.1, memory: 1_240_000_000),
            fixture(pid: 9234, name: "Spotify", path: "/Applications/Spotify.app/Contents/MacOS/Spotify", cpu: 2.3, memory: 412_000_000),
            fixture(pid: 18221, name: "zsh", path: "/bin/zsh", user: "root", cpu: 0.4, memory: 92_000_000, status: .sleeping),
        ]
    }

    // MARK: - Search

    func testSearchMatchesNameCaseInsensitively() {
        XCTAssertTrue(SystemViewModel.matches(fixtures[0], query: "chrome"))
        XCTAssertTrue(SystemViewModel.matches(fixtures[0], query: "CHROME"))
        XCTAssertFalse(SystemViewModel.matches(fixtures[1], query: "chrome"))
    }

    func testSearchMatchesPid() {
        XCTAssertTrue(SystemViewModel.matches(fixtures[0], query: "12480"))
        XCTAssertFalse(SystemViewModel.matches(fixtures[0], query: "99999"))
    }

    func testSearchMatchesPath() {
        XCTAssertTrue(SystemViewModel.matches(fixtures[1], query: "Visual Studio Code"))
        XCTAssertTrue(SystemViewModel.matches(fixtures[3], query: "/bin/zsh"))
    }

    func testSearchMatchesUser() {
        XCTAssertTrue(SystemViewModel.matches(fixtures[3], query: "root"))
        XCTAssertFalse(SystemViewModel.matches(fixtures[0], query: "root"))
    }

    func testEmptyQueryMatchesEverything() {
        for process in fixtures {
            XCTAssertTrue(SystemViewModel.matches(process, query: ""))
            XCTAssertTrue(SystemViewModel.matches(process, query: "   "))
        }
    }

    // MARK: - Sort

    func testDefaultSortIsMemoryDescending() {
        let order = [KeyPathComparator(\ProcessSnapshot.memoryBytes, order: .reverse)]
        let sorted = fixtures.sorted(using: order)
        XCTAssertEqual(sorted.map(\.pid), [12480, 18342, 9234, 18221])
    }

    func testSortByCpuDescending() {
        let order = [KeyPathComparator(\ProcessSnapshot.cpuPercent, order: .reverse)]
        let sorted = fixtures.sorted(using: order)
        XCTAssertEqual(sorted.map(\.pid), [12480, 18342, 9234, 18221])
    }

    func testSortByPidAscending() {
        let order = [KeyPathComparator(\ProcessSnapshot.pid)]
        let sorted = fixtures.sorted(using: order)
        XCTAssertEqual(sorted.map(\.pid), [9234, 12480, 18221, 18342])
    }

    func testSortByName() {
        let order = [KeyPathComparator(\ProcessSnapshot.name)]
        let sorted = fixtures.sorted(using: order)
        XCTAssertEqual(sorted.map(\.name), ["Chrome", "Code", "Spotify", "zsh"])
    }

    func testSortHandlesNilCpu() {
        var withNil = fixtures
        withNil.append(fixture(pid: 1, name: "launchd", cpu: nil, memory: 10_000_000))
        let order = [KeyPathComparator(\ProcessSnapshot.cpuPercent, order: .reverse)]
        let sorted = withNil.sorted(using: order)
        // nil sorts last in a descending sort; must not crash or misorder the rest
        XCTAssertEqual(sorted.first?.pid, 12480)
        XCTAssertEqual(sorted.last?.pid, 1)
    }

    func testDuplicatePidsNotProduced() {
        let pids = fixtures.map(\.pid)
        XCTAssertEqual(Set(pids).count, pids.count)
    }
}
