import Foundation

/// Reads Codex/ChatGPT's real usage from the `rate_limits` snapshot Codex writes
/// into its rollout logs — the same percentages ChatGPT/Codex servers report:
///   payload.rate_limits.primary  (window_minutes 300 = 5h)
///   payload.rate_limits.secondary(window_minutes 10080 = 7d)
/// The newest rollout's last snapshot is the current state.
final class CodexRateLimitReader: @unchecked Sendable {
    private let root: URL
    private let fm = FileManager.default

    init(root: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")) {
        self.root = root
    }

    func fetch() -> ProviderUsage {
        guard let file = newestRollout() else { return .unavailable }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return .unavailable }

        // Walk lines from the end; first one carrying rate_limits wins.
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("rate_limits"),
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rl = findRateLimits(obj) else { continue }

            return ProviderUsage(
                fiveHour: window(rl["primary"]),
                sevenDay: window(rl["secondary"]),
                live: true, note: nil)
        }
        return .unavailable
    }

    private func window(_ any: Any?) -> WindowUsage? {
        guard let d = any as? [String: Any],
              let pct = (d["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let resets = (d["resets_at"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue)
        }
        return WindowUsage(utilization: pct, resetsAt: resets)
    }

    private func findRateLimits(_ any: Any) -> [String: Any]? {
        if let d = any as? [String: Any] {
            if let rl = d["rate_limits"] as? [String: Any] { return rl }
            for (_, v) in d { if let f = findRateLimits(v) { return f } }
        }
        return nil
    }

    private func newestRollout() -> URL? {
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return nil }

        var newest: (URL, Date)?
        for case let url as URL in en
        where url.lastPathComponent.hasPrefix("rollout-") && url.pathExtension == "jsonl" {
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            if newest == nil || d > newest!.1 { newest = (url, d) }
        }
        return newest?.0
    }
}
