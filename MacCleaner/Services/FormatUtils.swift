import Foundation

/// Native-feel formatting for byte counts and percentages.
/// Unknown values are rendered as "—", never as a fabricated zero.
enum FormatUtils {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.includesUnit = true
        return formatter
    }()

    /// e.g. "1.82 GB", "412 MB", "96 KB".
    static func byteCount(_ bytes: UInt64) -> String {
        // ByteCountFormatter takes Int64; clamp to avoid overflow on absurd values.
        let clamped = bytes > UInt64(Int64.max) ? Int64.max : Int64(bytes)
        return byteFormatter.string(fromByteCount: clamped)
    }

    static func byteCount(_ bytes: UInt64?) -> String {
        guard let bytes else { return unavailable }
        return byteCount(bytes)
    }

    /// e.g. "38.7%".
    static func percent(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", value)
    }

    static func percent(_ value: Double?, digits: Int = 1) -> String {
        guard let value else { return unavailable }
        return percent(value, digits: digits)
    }

    /// e.g. "3.2 GHz".
    static func frequency(_ hz: UInt64?) -> String {
        guard let hz, hz > 0 else { return unavailable }
        return String(format: "%.2f GHz", Double(hz) / 1_000_000_000)
    }

    static let unavailable = "—"
}
