import XCTest
@testable import MacCleaner

final class FormatUtilsTests: XCTestCase {

    func testByteCountUsesNativeUnits() {
        XCTAssertTrue(FormatUtils.byteCount(0).contains("0"))
        XCTAssertTrue(FormatUtils.byteCount(512).contains("KB") || FormatUtils.byteCount(512).contains("byte"))
        XCTAssertTrue(FormatUtils.byteCount(1_824_000_000).contains("GB"))
        XCTAssertTrue(FormatUtils.byteCount(412_000_000).contains("MB"))
    }

    func testByteCountNilIsUnavailable() {
        XCTAssertEqual(FormatUtils.byteCount(nil), "—")
    }

    func testPercentFormatting() {
        XCTAssertEqual(FormatUtils.percent(38.74), "38.7%")
        XCTAssertEqual(FormatUtils.percent(100.0), "100.0%")
        XCTAssertEqual(FormatUtils.percent(0.0), "0.0%")
    }

    func testPercentNilIsUnavailable() {
        XCTAssertEqual(FormatUtils.percent(nil), "—")
    }

    func testFrequencyUnavailableWhenZero() {
        XCTAssertEqual(FormatUtils.frequency(0), "—")
        XCTAssertEqual(FormatUtils.frequency(nil), "—")
        XCTAssertTrue(FormatUtils.frequency(3_200_000_000).contains("GHz"))
    }
}
