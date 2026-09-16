import Foundation
import Security

/// Fetches Claude's real usage from the same endpoint the Claude app uses:
/// GET https://api.anthropic.com/api/oauth/usage  (Bearer = Keychain OAuth token).
/// Returns the provider's own `five_hour` / `seven_day` utilization — the exact
/// number shown in the app, not a token-sum reconstruction.
final class ClaudeUsageAPI: @unchecked Sendable {
    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Synchronous; call off the main thread.
    func fetch() -> ProviderUsage {
        guard let token = oauthToken() else {
            return ProviderUsage(fiveHour: nil, sevenDay: nil, live: false, note: "no credentials")
        }

        var req = URLRequest(url: endpoint, timeoutInterval: 15)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var result = ProviderUsage.unavailable
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 || code == 403 {
                result = ProviderUsage(fiveHour: nil, sevenDay: nil, live: false, note: "re-login")
                return
            }
            guard code == 200, let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            result = ProviderUsage(
                fiveHour: Self.window(obj["five_hour"]),
                sevenDay: Self.window(obj["seven_day"]),
                live: true, note: nil)
        }.resume()
        _ = sem.wait(timeout: .now() + 16)
        return result
    }

    private static func window(_ any: Any?) -> WindowUsage? {
        guard let d = any as? [String: Any],
              let util = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
        return WindowUsage(utilization: util,
                           resetsAt: ProviderUsage.parseISO(d["resets_at"] as? String))
    }

    /// Reads the OAuth access token from the Keychain item Claude Code created.
    /// This reads the secret (needs it for the Bearer), so macOS prompts for access
    /// on first run — choose "Always Allow".
    private func oauthToken() -> String? {
        for query in keychainQueries() {
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let holder = (obj["claudeAiOauth"] as? [String: Any]) ?? obj
            if let tok = holder["accessToken"] as? String ?? holder["access_token"] as? String {
                return tok
            }
        }
        return nil
    }

    private func keychainQueries() -> [[String: Any]] {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return [
            base.merging([kSecAttrService as String: "Claude Code-credentials"]) { _, b in b },
            base.merging([kSecAttrAccount as String: "Claude Code-credentials"]) { _, b in b }
        ]
    }
}
