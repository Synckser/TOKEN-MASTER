import Foundation

/// A single opt-in suggestion. `apply` is nil for purely informational advice.
struct Recommendation: Identifiable {
    let id = UUID()
    let title: String
    let rationale: String
    let estimatedSaving: String
    /// Performs the change (backup first) and returns a user-facing result string.
    let apply: (() throws -> String)?
}

/// A rule inspects the store (and config on disk) and may emit one recommendation.
protocol Rule {
    @MainActor func evaluate(_ store: UsageStore) -> Recommendation?
}

/// Runs all v1 rules and collects their recommendations.
final class Advisor {
    private let rules: [Rule] = [
        PromptCachingRule(),
        RouteToHaikuRule(),
        ClearVsCompactRule(),
        CompressConfigRule(),
        CavemanRule()
    ]

    @MainActor
    func recommendations(for store: UsageStore) -> [Recommendation] {
        rules.compactMap { $0.evaluate(store) }
    }

    /// Copies `url` to `url.bak` (overwriting any prior backup). Reversible by
    /// restoring the .bak. Used by rules whose apply() touches a config file.
    static func backup(_ url: URL) throws -> URL {
        let bak = url.appendingPathExtension("bak")
        let fm = FileManager.default
        if fm.fileExists(atPath: bak.path) { try fm.removeItem(at: bak) }
        try fm.copyItem(at: url, to: bak)
        return bak
    }
}
