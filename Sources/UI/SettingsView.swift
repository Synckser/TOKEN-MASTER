import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @Bindable var store: UsageStore
    @Bindable private var prefs = Prefs.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    // Claude account (own OAuth) state.
    @State private var connected = ClaudeOAuth.shared.isConnected
    @State private var pastedCode = ""
    @State private var signingIn = false
    @State private var authError: String?

    var body: some View {
        Form {
            Section("Claude account") {
                if connected {
                    LabeledContent("Status") {
                        Label("Connected", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    Text("TOKEN MASTER uses its own token for live, accurate Claude usage.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Sign out") {
                        ClaudeOAuth.shared.signOut()
                        connected = false; signingIn = false; pastedCode = ""
                    }
                } else if signingIn {
                    Text("1. A Claude page opened in your browser. Approve access.\n"
                        + "2. Copy the code it shows and paste it here:")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Paste code", text: $pastedCode)
                            .textFieldStyle(.roundedBorder)
                        Button("Connect") { connect() }
                            .buttonStyle(.borderedProminent)
                            .disabled(pastedCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Button("Cancel") { signingIn = false; pastedCode = "" }
                    if let authError {
                        Text(authError).font(.caption).foregroundStyle(.red)
                    }
                } else {
                    Text("Sign in so the meter reads your live Claude usage (its own token "
                        + "avoids the shared rate limit).")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Sign in to Claude") {
                        let url = ClaudeOAuth.shared.authorizeURLString()
                        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                        signingIn = true; authError = nil
                    }
                }
            }

            Section("Usage budgets (fallback only)") {
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

    private func connect() {
        do {
            try ClaudeOAuth.shared.completeLogin(pasted: pastedCode)
            connected = true
            signingIn = false
            pastedCode = ""
            authError = nil
            store.forceUsageNow()   // fetch live immediately with the new token
        } catch {
            authError = error.localizedDescription
        }
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
