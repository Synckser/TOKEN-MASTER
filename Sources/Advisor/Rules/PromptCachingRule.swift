import Foundation

/// Flags a low prompt-cache hit rate — the single biggest avoidable token cost.
struct PromptCachingRule: Rule {
    @MainActor func evaluate(_ store: UsageStore) -> Recommendation? {
        guard store.last7dTokens > 50_000 else { return nil }
        let ratio = store.cacheHitRatio
        guard ratio < 0.30 else { return nil }
        return Recommendation(
            title: "Low cache hit rate (\(Format.percent(ratio)))",
            rationale: "Only \(Format.percent(ratio)) of input tokens are served from "
                + "prompt cache. Keep stable content (system prompt, tool list) first and "
                + "unchanged so the cached prefix survives across turns.",
            estimatedSaving: "Cache reads cost ~10% of fresh input.",
            apply: nil
        )
    }
}
