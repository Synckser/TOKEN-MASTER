import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Bindable private var prefs = Prefs.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Form {
            Section("Usage budgets (per 5h window)") {
                budgetField("Claude", millions($prefs.claudeBudget5h))
                budgetField("ChatGPT / Codex", millions($prefs.codexBudget5h))
                Text("The meter fills toward this. Set it to the comfortable ceiling for "
                    + "your plan; the ring goes red as you approach it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Meter colors") {
                thresholdSlider("Green → Blue at", value: $prefs.cautionThreshold,
                                range: 0.2...(prefs.dangerThreshold - 0.05))
                thresholdSlider("Blue → Red at", value: $prefs.dangerThreshold,
                                range: (prefs.cautionThreshold + 0.05)...0.98)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunch(on) }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.1")
                Text("Local token meter for Claude Code + ChatGPT/Codex. Reads only your "
                    + "own log files; nothing leaves this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 420)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    // MARK: Budget field (edited in millions of tokens)

    private func budgetField(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("", value: value, format: .number.precision(.fractionLength(0...1)))
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
            Text("M tokens").foregroundStyle(.secondary)
        }
    }

    private func thresholdSlider(_ label: String, value: Binding<Double>,
                                 range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(Format.percent(value.wrappedValue)).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range.lowerBound < range.upperBound ? range : 0.2...0.98)
        }
    }

    /// Bridges an Int token budget to a Double edited in millions.
    private func millions(_ b: Binding<Int>) -> Binding<Double> {
        Binding(
            get: { Double(b.wrappedValue) / 1_000_000 },
            set: { b.wrappedValue = max(0, Int($0 * 1_000_000)) }
        )
    }

    private func setLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
