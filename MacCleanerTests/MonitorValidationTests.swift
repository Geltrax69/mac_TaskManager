import Darwin
import XCTest
@testable import MacCleaner

/// Tests for PID validation, kernel-status mapping, and errno mapping.
/// No process is ever signaled by these tests.
final class MonitorValidationTests: XCTestCase {

    // MARK: - PID validation

    func testZeroPidIsInvalid() {
        XCTAssertThrowsError(try MacOSSystemMonitor.validatePid(0)) { error in
            guard case MonitorError.invalidPid(0) = error else {
                return XCTFail("expected .invalidPid, got \(error)")
            }
        }
    }

    func testNegativePidIsInvalid() {
        XCTAssertThrowsError(try MacOSSystemMonitor.validatePid(-5))
    }

    func testPositivePidIsValid() {
        XCTAssertNoThrow(try MacOSSystemMonitor.validatePid(1234))
    }

    // MARK: - Status mapping

    func testKernelStatusMapping() {
        XCTAssertEqual(MacOSSystemMonitor.status(for: SIDL), .idle)
        XCTAssertEqual(MacOSSystemMonitor.status(for: SRUN), .running)
        XCTAssertEqual(MacOSSystemMonitor.status(for: SSLEEP), .sleeping)
        XCTAssertEqual(MacOSSystemMonitor.status(for: SSTOP), .stopped)
        XCTAssertEqual(MacOSSystemMonitor.status(for: SZOMB), .zombie)
        XCTAssertEqual(MacOSSystemMonitor.status(for: 999), .unknown)
    }

    // MARK: - errno mapping

    func testErrnoMapsToFriendlyErrors() {
        errno = ESRCH
        if case .processNotFound(42) = MacOSSystemMonitor.errnoError(pid: 42, operation: "terminate") {
        } else {
            XCTFail("ESRCH should map to .processNotFound")
        }

        errno = EPERM
        if case .accessDenied(let message) = MacOSSystemMonitor.errnoError(pid: 42, operation: "terminate") {
            XCTAssertTrue(message.contains("elevated privileges") || message.contains("protected"))
        } else {
            XCTFail("EPERM should map to .accessDenied")
        }

        errno = EINVAL
        if case .terminationFailed = MacOSSystemMonitor.errnoError(pid: 42, operation: "terminate") {
        } else {
            XCTFail("other errnos should map to .terminationFailed")
        }
        errno = 0
    }

    // MARK: - Memory math

    func testMemoryUsagePercent() {
        let info = MemoryInfo(totalBytes: 32_000_000_000, usedBytes: 12_400_000_000,
                             swapUsedBytes: nil, swapTotalBytes: nil)
        XCTAssertEqual(info.usagePercent ?? -1, 38.75, accuracy: 0.001)
        XCTAssertEqual(info.availableBytes, 19_600_000_000)
    }

    func testMemoryPercentNilWhenUnknown() {
        let unknownTotal = MemoryInfo(totalBytes: 0, usedBytes: 100, swapUsedBytes: nil, swapTotalBytes: nil)
        XCTAssertNil(unknownTotal.usagePercent)
        let unknownUsed = MemoryInfo(totalBytes: 100, usedBytes: nil, swapUsedBytes: nil, swapTotalBytes: nil)
        XCTAssertNil(unknownUsed.usagePercent)
        XCTAssertNil(unknownUsed.availableBytes)
    }
}
