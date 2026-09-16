import Foundation

/// Estimates the next usage-window reset from a rolling window's oldest live event.
/// Purely local — labelled "estimate" in the UI, never presented as authoritative.
enum ResetEstimator {
    static let fiveHours: TimeInterval = 5 * 3600

    /// Next reset = (oldest event still inside the window) + window length.
    /// Returns nil if the window is currently empty.
    static func nextReset(events: [UsageEvent],
                          window: TimeInterval,
                          now: Date = Date()) -> Date? {
        let cutoff = now.addingTimeInterval(-window)
        guard let oldest = events.lazy
            .filter({ $0.timestamp >= cutoff })
            .map(\.timestamp)
            .min() else { return nil }
        return oldest.addingTimeInterval(window)
    }

    static func countdownString(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let secs = max(0, Int(date.timeIntervalSince(now)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
