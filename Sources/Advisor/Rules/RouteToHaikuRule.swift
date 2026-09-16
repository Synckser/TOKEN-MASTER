import Foundation

/// Suggests routing mechanical work to a cheaper model when thinking share is high.
struct RouteToHaikuRule: Rule {
    @MainActor func evaluate(_ store: UsageStore) -> Recommendation? {
        guard store.last7dTokens > 50_000 else { return nil }
        let share = store.thinkingShare
        guard share > 0.35 else { return nil }
        return Recommendation(
            title: "High thinking share (\(Format.percent(share)))",
            rationale: "\(Format.percent(share)) of output is reasoning tokens. Route "
                + "mechanical work — bulk rename, reformat, summarize, scrape, boilerplate — "
                + "to a Haiku subagent; keep architecture and debugging on the big model.",
            estimatedSaving: "Haiku output is ~1/5 the price of Opus.",
            apply: nil
        )
    }
}
