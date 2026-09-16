import Foundation

/// Reads Claude Code turn logs: ~/.claude/projects/**/*.jsonl.
/// Each assistant line carries `message.usage` with the token breakdown.
final class ClaudeUsageReader: IncrementalJSONLReader, UsageSource, @unchecked Sendable {
    let source: UsageEvent.Source = .claude
    let root: URL

    init(root: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")) {
        self.root = root
    }

    func scan() -> [UsageEvent] {
        guard fm.fileExists(atPath: root.path) else { return [] }
        var events: [UsageEvent] = []

        for file in files(under: root, matching: { $0.hasSuffix(".jsonl") }) {
            for line in newLines(in: file) {
                guard
                    let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                    let msg = obj["message"] as? [String: Any],
                    let usage = msg["usage"] as? [String: Any]
                else { continue }

                let input = int(usage, "input_tokens")
                let cacheCreate = int(usage, "cache_creation_input_tokens")
                let cacheRead = int(usage, "cache_read_input_tokens")
                let output = int(usage, "output_tokens")
                let thinking = (usage["output_tokens_details"] as? [String: Any])
                    .map { int($0, "thinking_tokens") } ?? 0

                // Skip empty usage rows (e.g. user turns that carry a stub).
                if input + cacheCreate + cacheRead + output == 0 { continue }

                events.append(UsageEvent(
                    source: .claude,
                    timestamp: parseDate(obj["timestamp"]) ?? Date(),
                    input: input,
                    cacheCreate: cacheCreate,
                    cacheRead: cacheRead,
                    output: output,
                    thinking: thinking
                ))
            }
        }
        return events
    }
}
