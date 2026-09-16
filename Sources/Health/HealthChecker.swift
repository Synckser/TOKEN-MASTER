import Foundation
import Security

enum HealthLight {
    case green, amber, red

    var symbol: String {
        switch self {
        case .green: return "circle.fill"
        case .amber: return "circle.fill"
        case .red:   return "circle.fill"
        }
    }
}

struct HealthStatus: Identifiable {
    let id = UUID()
    let source: UsageEvent.Source
    let light: HealthLight
    let detail: String
}

/// Read-only health checks. Never extracts secrets; caches nothing sensitive.
final class HealthChecker {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func check() -> [HealthStatus] {
        [checkClaude(), checkCodex()]
    }

    // MARK: Claude

    private func checkClaude() -> HealthStatus {
        let hasCreds = keychainItemPresent(service: "Claude Code-credentials")
            || keychainItemPresent(account: "Claude Code-credentials")
        let recent = recentActivity(in: home.appendingPathComponent(".claude/projects"),
                                    suffix: ".jsonl")
        let onPath = binaryOnPath("claude")

        if !hasCreds {
            return HealthStatus(source: .claude, light: .red,
                                detail: "Not logged in — no Keychain credentials found.")
        }
        if recent {
            return HealthStatus(source: .claude, light: .green,
                                detail: "Logged in\(onPath ? "" : " (CLI not on PATH)"), recent activity.")
        }
        return HealthStatus(source: .claude, light: .amber,
                            detail: "Logged in, no recent activity.")
    }

    // MARK: Codex

    private func checkCodex() -> HealthStatus {
        let authJSON = home.appendingPathComponent(".codex/auth.json")
        let configToml = home.appendingPathComponent(".codex/config.toml")
        let hasAuth = nonEmptyFile(authJSON) || nonEmptyFile(configToml)
        let recent = recentActivity(in: home.appendingPathComponent(".codex/sessions"),
                                    suffix: ".jsonl")

        if !hasAuth {
            return HealthStatus(source: .codex, light: .red,
                                detail: "No auth in ~/.codex.")
        }
        if recent {
            return HealthStatus(source: .codex, light: .green,
                                detail: "Configured, recent activity.")
        }
        return HealthStatus(source: .codex, light: .amber,
                            detail: "Configured, no recent activity.")
    }

    // MARK: Helpers

    /// Existence check via attributes only — no data read, so no auth prompt.
    private func keychainItemPresent(service: String? = nil, account: String? = nil) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let service { query[kSecAttrService as String] = service }
        if let account { query[kSecAttrAccount as String] = account }
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    private func nonEmptyFile(_ url: URL) -> Bool {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int else { return false }
        return size > 0
    }

    /// True if any matching file was modified within the last 24h.
    private func recentActivity(in root: URL, suffix: String, within: TimeInterval = 86_400) -> Bool {
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return false }

        let cutoff = Date().addingTimeInterval(-within)
        for case let url as URL in en where url.lastPathComponent.hasSuffix(suffix) {
            if let d = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate, d >= cutoff {
                return true
            }
        }
        return false
    }

    private func binaryOnPath(_ name: String) -> Bool {
        let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
            + ["/usr/local/bin", "/opt/homebrew/bin", "\(home.path)/.local/bin"]
        for d in dirs where fm.isExecutableFile(atPath: "\(d)/\(name)") {
            return true
        }
        return false
    }
}
