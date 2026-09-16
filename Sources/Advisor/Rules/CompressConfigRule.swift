import Foundation

/// Flags an oversized global CLAUDE.md / MEMORY.md — loaded into every session's
/// input. apply() backs the file up (.bak) so you can safely shrink it after.
struct CompressConfigRule: Rule {
    private let thresholdBytes = 8 * 1024

    private var targets: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/CLAUDE.md"),
            home.appendingPathComponent(".claude/projects/-Users-roberto/memory/MEMORY.md")
        ]
    }

    @MainActor func evaluate(_ store: UsageStore) -> Recommendation? {
        let fm = FileManager.default
        let oversized = targets.first { url in
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int else { return false }
            return size > thresholdBytes
        }
        guard let url = oversized,
              let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int
        else { return nil }

        let name = url.lastPathComponent
        return Recommendation(
            title: "\(name) is large (\(Format.compact(size)) B)",
            rationale: "\(name) loads into every session's input. Compressing it (e.g. "
                + "/caveman:compress) cuts recurring input tokens. Apply backs it up first.",
            estimatedSaving: "Recurring input savings every session.",
            apply: {
                let bak = try Advisor.backup(url)
                return "Backed up → \(bak.lastPathComponent). Now shrink \(name) "
                    + "(e.g. run /caveman:compress); restore from the .bak if needed."
            }
        )
    }
}
