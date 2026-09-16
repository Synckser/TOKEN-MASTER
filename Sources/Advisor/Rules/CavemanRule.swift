import Foundation

/// Suggests caveman mode for chat-heavy sessions to cut output tokens.
struct CavemanRule: Rule {
    @MainActor func evaluate(_ store: UsageStore) -> Recommendation? {
        let sevenDayOutput = store.events(since: Date().addingTimeInterval(-7 * 86_400))
            .reduce(0) { $0 + $1.output }
        guard sevenDayOutput > 200_000 else { return nil }
        return Recommendation(
            title: "High output volume — try caveman mode",
            rationale: "\(Format.compact(sevenDayOutput)) output tokens in 7 days. Caveman "
                + "mode drops articles/filler/pleasantries and cuts output ~75% while keeping "
                + "technical substance. Toggle with /caveman.",
            estimatedSaving: "~75% fewer output tokens on prose-heavy turns.",
            apply: nil
        )
    }
}
