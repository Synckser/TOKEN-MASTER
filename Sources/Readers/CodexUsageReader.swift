import Foundation

/// Reads Codex session logs: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl.
/// Lines carry a cumulative `total_token_usage`; we diff consecutive snapshots
/// per file into per-turn events so rolling windows are accurate.
final class CodexUsageReader: IncrementalJSONLReader, UsageSource, @unchecked Sendable {
    let source: UsageEvent.Source = .codex
    let root: URL

    /// Last cumulative snapshot seen per file: (input, cacheRead, output, thinking).
    private var lastCumulative: [String: (Int, Int, Int, Int)] = [:]

    init(root: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")) {
        self.root = root
    }

    func scan() -> [UsageEvent] {
        guard fm.fileExists(atPath: root.path) else { return [] }
        var events: [UsageEvent] = []

        for file in files(under: root, matching: {
            $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl")
        }) {
            let path = file.path
            for line in newLines(in: file) {
                guard let obj = try? JSONSerialization.jsonObject(with: line) else { continue }
                guard let usage = findDict(obj, key: "total_token_usage") else { continue }

                let input = int(usage, "input_tokens")
                let cachedInput = int(usage, "cached_input_tokens")
                let output = int(usage, "output_tokens")
                let thinking = int(usage, "reasoning_output_tokens")

                let cur = (input, cachedInput, output, thinking)
                let prev = lastCumulative[path] ?? (0, 0, 0, 0)

                // Cumulative should only grow; a decrease means a reset — rebase.
                let base = (cur.0 >= prev.0 && cur.2 >= prev.2) ? prev : (0, 0, 0, 0)
                lastCumulative[path] = cur

                let dInput = max(0, cur.0 - base.0)        // total input incl. cached
                let dCached = max(0, cur.1 - base.1)
                let dOutput = max(0, cur.2 - base.2)
                let dThink = max(0, cur.3 - base.3)
                let dFresh = max(0, dInput - dCached)       // uncached input

                if dInput + dOutput == 0 { continue }

                events.append(UsageEvent(
                    source: .codex,
                    timestamp: parseDate(obj is [String: Any] ? (obj as! [String: Any])["timestamp"] : nil)
                        ?? fileDate(file),
                    input: dFresh,
                    cacheCreate: 0,
                    cacheRead: dCached,
                    output: dOutput,
                    thinking: dThink
                ))
            }
        }
        return events
    }

    private func fileDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
    }
}
