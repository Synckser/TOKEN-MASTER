import SwiftUI
import AppKit

struct MenuView: View {
    @Bindable var store: UsageStore
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
            recommendationsSection
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
        let used = store.window5hTokens(source: s)
        let budget = store.budget(s)
        let status = store.status(s)
        return VStack(spacing: 5) {
            HStack(spacing: 10) {
                RingGauge(fraction: store.fraction(s), status: status,
                          letter: letter, size: 30, lineWidth: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.display).font(.subheadline).bold()
                    Text("\(Format.compact(used)) / \(Format.compact(budget)) · \(Format.percent(store.fraction(s)))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
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

    // MARK: Recommendations

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recommendations").font(.caption).bold().foregroundStyle(.secondary)
            if store.recommendations.isEmpty {
                Text("Nothing to suggest — usage looks efficient.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(store.recommendations) { rec in
                    recommendationRow(rec)
                }
            }
        }
    }

    private func recommendationRow(_ rec: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rec.title).font(.caption).bold()
            Text(rec.rationale).font(.caption2).foregroundStyle(.secondary)
            HStack {
                Text(rec.estimatedSaving).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if let apply = rec.apply {
                    Button("Apply") {
                        do { applied[rec.id] = try apply(); applyError[rec.id] = nil }
                        catch { applyError[rec.id] = error.localizedDescription }
                    }
                    .buttonStyle(.borderless).font(.caption2)
                }
            }
            if let msg = applied[rec.id] {
                Text(msg).font(.caption2).foregroundStyle(.green)
            }
            if let err = applyError[rec.id] {
                Text(err).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Refresh") { store.refresh(); store.updateHealthAndAdvice() }
                .font(.caption2)
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
