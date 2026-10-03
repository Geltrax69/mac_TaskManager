import SwiftUI

/// Placeholder for the storage-cleaning side of the app.
/// The System tab is the fully-built feature; this keeps the app shell honest.
struct CleanTabView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Clean")
                .font(.title2.bold())
            Text("Storage cleaning tools will live here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
