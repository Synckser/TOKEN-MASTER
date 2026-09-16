import Foundation

/// Reminds to prefer /clear over /compact between unrelated jobs.
struct ClearVsCompactRule: Rule {
    @MainActor func evaluate(_ store: UsageStore) -> Recommendation? {
        guard store.window5hTokens > 200_000 else { return nil }
        return Recommendation(
            title: "Heavy current window — use /clear between jobs",
            rationale: "You've moved \(Format.compact(store.window5hTokens)) tokens in the "
                + "last 5h. Between unrelated tasks, /clear resets context instead of "
                + "/compact, which re-summarizes (and re-bills) the whole history.",
            estimatedSaving: "Avoids re-summarizing carried-over context.",
            apply: nil
        )
    }
}
