import SwiftUI

/// Compact strip of the top memory consumers. Tapping one selects it
/// in the main table.
struct TopMemoryView: View {
    let processes: [ProcessSnapshot]
    var onSelect: (pid_t) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top Memory".uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(processes.enumerated()), id: \.element.pid) { index, process in
                    Button {
                        onSelect(process.pid)
                    } label: {
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                                .frame(width: 14, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(process.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(FormatUtils.byteCount(process.memoryBytes))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .help("Select \(process.name) (PID \(process.pid)) in the table")
                }
            }
        }
    }
}
