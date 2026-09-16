import SwiftUI
import AppKit

struct MenuView: View {
    @Bindable var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @State private var applied: [UUID: String] = [:]
    @State private var applyError: [UUID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            meterRow(.claude, letter: "C")
            meterRow(.codex, letter: "G")
            Divider()
            windowBreakdown
            Divider()
            healthSection
            Divider()
            optimizeSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("TOKEN MASTER").font(.headline)
            Spacer()
            if let last = store.lastRefresh {
                Text(last, style: .time)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Per-source meters (the glanceable headline)

    private func meterRow(_ s: UsageEvent.Source, letter: String) -> some View {
        let status = store.status(s)
        let live = store.isLive(s)
        let used = store.window5hTokens(source: s)
        return VStack(spacing: 5) {
            HStack(spacing: 10) {
                RingGauge(fraction: store.fraction(s), status: status,
                          letter: letter, size: 30, lineWidth: 4)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(s.display).font(.subheadline).bold()
                        Text(store.percentText(s))
                            .font(.subheadline).bold().foregroundStyle(status.color)
                            .monospacedDigit()
                    }
                    Text(subtitle(s, used: used, live: live))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(status.text).font(.caption2).bold().foregroundStyle(status.color)
                    Text("resets ~\(ResetEstimator.countdownString(to: store.nextReset(s)))")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            ProgressView(value: store.fraction(s))
                .tint(status.color)
        }
    }

    /// Secondary line: 7-day util when live, plus this-window token volume; or a
    /// fallback note when the provider number isn't available.
    private func subtitle(_ s: UsageEvent.Source, used: Int, live: Bool) -> String {
        if live {
            var parts = ["5h window"]
            if let week = store.sevenDayUtilization(s) { parts.append("7d \(Int(week.rounded()))%") }
            parts.append("\(Format.compact(used)) tok")
            return parts.joined(separator: " · ")
        }
        if let note = store.providerUsage(s).note {
            return "estimate — \(note)"
        }
        return "estimate · \(Format.compact(used)) / \(Format.compact(store.budget(s))) tok"
    }

    // MARK: Windows

    private var windowBreakdown: some View {
        VStack(spacing: 4) {
            row("Today", store.todayTokens, cost: nil)
            row("Last 7 days", store.last7dTokens, cost: store.cost7d())
            statRow("Cache hits", Format.percent(store.cacheHitRatio))
            statRow("Thinking share", Format.percent(store.thinkingShare))
        }
    }

    private func row(_ label: String, _ tokens: Int, cost: Double?) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let cost { Text(Format.usd(cost)).font(.caption2).foregroundStyle(.secondary) }
            Text(Format.compact(tokens)).font(.caption).monospacedDigit()
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).monospacedDigit()
        }
    }

    // MARK: Health

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.health) { h in
                HStack(spacing: 8) {
                    Circle().fill(color(h.light)).frame(width: 9, height: 9)
                    Text(h.source.display).font(.caption).bold()
                    Text(h.detail).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func color(_ l: HealthLight) -> Color {
        switch l {
        case .green: return .green
        case .amber: return .orange
        case .red:   return .red
        }
    }

    // MARK: Optimize teaser

    private var optimizeSection: some View {
        let optimizer = Optimizer(store: store)
        let saved = optimizer.totalSavedTokens()
        return Button {
            openWindow(id: "optimizer")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack {
                Image(systemName: "bolt.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Optimize").font(.caption).bold()
                    Text(saved > 0 ? "≈ \(Format.compact(saved)) tokens saved so far"
                                   : "Apply token-saving changes")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Refresh") { store.refresh(); store.updateHealthAndAdvice() }
                .font(.caption2)
            SettingsLink { Text("Settings").font(.caption2) }
            Spacer()
            Button("Repo") {
                if let url = URL(string: "https://github.com/Synckser/TOKEN-MASTER") {
                    NSWorkspace.shared.open(url)
                }
            }.font(.caption2)
            Button("Quit") { NSApp.terminate(nil) }.font(.caption2)
        }
        .buttonStyle(.borderless)
    }
}
