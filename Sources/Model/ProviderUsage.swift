import Foundation

/// One rate-limit window's real utilization, as reported by the provider itself.
struct WindowUsage: Codable {
    let utilization: Double   // percent, 0…100+ (provider's own number)
    let resetsAt: Date?
}

/// A provider's real usage, straight from its own accounting (not reconstructed).
struct ProviderUsage: Codable {
    let fiveHour: WindowUsage?
    let sevenDay: WindowUsage?
    let live: Bool            // true = fetched successfully this cycle
    let note: String?         // e.g. "re-login" when the token is stale

    static let unavailable = ProviderUsage(fiveHour: nil, sevenDay: nil,
                                           live: false, note: nil)

    /// ISO8601 with/without fractional seconds and timezone offsets.
    static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
