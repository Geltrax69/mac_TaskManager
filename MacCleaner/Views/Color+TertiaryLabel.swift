import SwiftUI

extension Color {
    /// Tertiary label color. `Color` has no `.tertiary` member (that's a
    /// `ShapeStyle`), and `Text.foregroundStyle` needs macOS 14 — so this
    /// AppKit semantic color is the macOS 13-compatible equivalent.
    static var tertiaryLabel: Color { Color(nsColor: .tertiaryLabelColor) }
}
