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
            if code == 429 {
                result = ProviderUsage(fiveHour: nil, sevenDay: nil, live: false, note: "rate_limited")
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
    ///
    /// We shell out to `/usr/bin/security` rather than use SecItem directly: the
    /// keychain ACL trusts the *accessing binary*, and an unsigned app's identity
    /// changes on every rebuild (so "Always Allow" never sticks). `security` is a
    /// stable, already-trusted accessor, so the grant persists. User approves the
    /// SecurityAgent prompt once ("Always Allow").
    private func oauthToken() -> String? {
        for lookup in [["-s", "Claude Code-credentials"], ["-a", "Claude Code-credentials"]] {
            guard let data = runSecurity(["find-generic-password"] + lookup + ["-w"]),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let holder = (obj["claudeAiOauth"] as? [String: Any]) ?? obj
            if let tok = holder["accessToken"] as? String ?? holder["access_token"] as? String {
                return tok
            }
        }
        return nil
    }

    private func runSecurity(_ args: [String]) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return data
    }
}
