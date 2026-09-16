import SwiftUI

/// Full optimization surface: two sections (Claude / ChatGPT-Codex), each a list
/// of applyable, reversible changes plus the running tokens-saved ledger.
struct OptimizerView: View {
    @Bindable var store: UsageStore
    @Bindable private var ledger = SavingsLedger.shared
    @State private var source: UsageEvent.Source = .claude

    var body: some View {
        let optimizer = Optimizer(store: store)
        let opts = optimizer.optimizations(for: source)

        return VStack(alignment: .leading, spacing: 14) {
            Text("Optimize")
                .font(.title2).bold()

            Picker("", selection: $source) {
                Text("Claude / Claude Code").tag(UsageEvent.Source.claude)
                Text("ChatGPT / Codex").tag(UsageEvent.Source.codex)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            savingsBanner(optimizer)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(opts) { opt in
                        OptimizationCard(opt: opt, optimizer: optimizer)
                            .id(opt.id + String(ledger.entries.count))
                    }
                }
            }

            Text("Estimates. File changes back up first (.bak) and are reversible. "
                + "Savings accrue as sessions run.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(minWidth: 460, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func savingsBanner(_ optimizer: Optimizer) -> some View {
        let saved = optimizer.savedTokens(for: source)
        let cost = optimizer.savedCost(for: source)
        let util = store.utilization(source)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("≈ \(Format.compact(saved))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.green)
                Text("tokens saved").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let cost { Text("≈ \(Format.usd(cost))").font(.headline).foregroundStyle(.green) }
            }
            HStack(spacing: 12) {
                if let util {
                    Label("\(Int(util.rounded()))% used now", systemImage: "gauge.medium")
                }
                let active = ledger.entries.filter { $0.source == source.rawValue }.count
                Label("\(active) active", systemImage: "checkmark.seal")
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct OptimizationCard: View {
    let opt: Optimization
    let optimizer: Optimizer
    @Bindable private var ledger = SavingsLedger.shared
    @State private var error: String?

    var body: some View {
        let applied = ledger.isApplied(opt.id)
        let saved = optimizer.savedTokens(entryFor: opt)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: opt.action == .fileApply ? "wrench.and.screwdriver.fill" : "lightbulb.fill")
                    .foregroundStyle(applied ? .green : .secondary)
                Text(opt.title).font(.headline)
                Spacer()
                Text(opt.saving)
                    .font(.caption2).bold()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.blue.opacity(0.15), in: Capsule())
            }

            Text(opt.why).font(.callout).foregroundStyle(.secondary)

            HStack {
                Text(opt.cite).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                actionArea(applied: applied, saved: saved)
            }

            if let error {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(applied ? .green.opacity(0.5) : .clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func actionArea(applied: Bool, saved: Int) -> some View {
        if applied {
            HStack(spacing: 10) {
                Text("✓ saved ≈ \(Format.compact(saved)) tok")
                    .font(.caption2).foregroundStyle(.green).monospacedDigit()
                Button("Undo") {
                    do { try optimizer.undo(opt); error = nil }
                    catch { self.error = error.localizedDescription }
                }
                .controlSize(.small)
            }
        } else if opt.available {
            Button(opt.action == .fileApply ? "Apply" : "Enable tracking") {
                do { try optimizer.apply(opt); error = nil }
                catch { self.error = error.localizedDescription }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        } else {
            Text("Not needed now").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
