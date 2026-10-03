import SwiftUI

/// Thin animated gauge used in the resource cards.
/// The 250ms ease-out is functional (it smooths 2s-interval updates),
/// not decorative — gauges shouldn't jump.
struct MeterBar: View {
    /// 0...1, or nil when unknown.
    let fraction: Double?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.35))
                if let fraction {
                    let clamped = min(max(fraction, 0), 1)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint(for: clamped))
                        .frame(width: geometry.size.width * clamped)
                        .animation(.easeOut(duration: 0.25), value: clamped)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private func tint(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return .green
        case ..<0.85: return .yellow
        default: return .red
        }
    }
}

private struct Card<Content: View>: View {
    let icon: String
    let title: String
    let content: Content

    init(icon: String, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
    }
}

struct ResourceCardsView: View {
    let snapshot: SystemSnapshot?

    var body: some View {
        HStack(spacing: 12) {
            ramCard
            cpuCard
            processesCard
        }
    }

    // MARK: - RAM

    private var ramCard: some View {
        Card(icon: "memorychip", title: "RAM") {
            VStack(alignment: .leading, spacing: 6) {
                if let memory = snapshot?.memory {
                    Text("\(FormatUtils.byteCount(memory.usedBytes)) / \(FormatUtils.byteCount(memory.totalBytes))")
                        .font(.title3.bold())
                        .monospacedDigit()
                    MeterBar(fraction: (memory.usagePercent ?? 0) / 100)
                    footnote("\(FormatUtils.percent(memory.usagePercent)) used · \(FormatUtils.byteCount(memory.availableBytes)) available")
                    if let swapUsed = memory.swapUsedBytes, let swapTotal = memory.swapTotalBytes, swapTotal > 0 {
                        footnote("Swap \(FormatUtils.byteCount(swapUsed)) / \(FormatUtils.byteCount(swapTotal))")
                    }
                } else {
                    Text(FormatUtils.unavailable).font(.title3.bold())
                    MeterBar(fraction: nil)
                    footnote("Loading…")
                }
            }
        }
        .help("Physical memory. Swap is reported separately and never counted as RAM.")
    }

    // MARK: - CPU

    private var cpuCard: some View {
        Card(icon: "cpu", title: "CPU") {
            VStack(alignment: .leading, spacing: 6) {
                if let cpu = snapshot?.cpu {
                    Text(FormatUtils.percent(cpu.overallPercent))
                        .font(.title3.bold())
                        .monospacedDigit()
                    MeterBar(fraction: (cpu.overallPercent ?? 0) / 100)
                    let details: String = {
                        var text = "\(cpu.logicalCores) logical cores"
                        if let physical = cpu.physicalCores {
                            text += " · \(physical) physical"
                        }
                        return text
                    }()
                    footnote(details)
                    footnote("Frequency \(FormatUtils.frequency(cpu.frequencyHz))")
                } else {
                    Text(FormatUtils.unavailable).font(.title3.bold())
                    MeterBar(fraction: nil)
                    footnote("Loading…")
                }
            }
        }
        .help("Overall utilization across all cores. Per-process values use 100% = one core.")
    }

    // MARK: - Processes

    private var processesCard: some View {
        Card(icon: "chart.bar", title: "Processes") {
            VStack(alignment: .leading, spacing: 6) {
                if let snapshot {
                    Text("\(snapshot.totalCount)")
                        .font(.title3.bold())
                        .monospacedDigit()
                    + Text(" running").font(.subheadline).foregroundStyle(.secondary)
                    MeterBar(fraction: nil)
                    footnote("\(snapshot.applicationCount) applications · \(snapshot.backgroundCount) background")
                } else {
                    Text(FormatUtils.unavailable).font(.title3.bold())
                    MeterBar(fraction: nil)
                    footnote("Loading…")
                }
            }
        }
        .help("Applications are processes running from inside an .app bundle.")
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }
}
