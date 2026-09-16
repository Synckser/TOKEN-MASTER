import Foundation
import Observation

/// Central aggregator. Owns readers, watcher, refresh timer; exposes rolling-window
/// stats to SwiftUI. Mutated only on the main actor.
@MainActor
@Observable
final class UsageStore {
    // Rolling window of events (kept to 7 days for windowed stats).
    private(set) var events: [UsageEvent] = []
    private(set) var health: [HealthStatus] = []
    private(set) var recommendations: [Recommendation] = []
    private(set) var lastRefresh: Date?

    // Real provider-reported usage (the accurate source; nil until first fetch).
    private(set) var claudeUsage: ProviderUsage = .unavailable
    private(set) var codexUsage: ProviderUsage = .unavailable

    // All-time accumulators (survive event pruning; reset per launch).
    private(set) var allTimeTokens: [UsageEvent.Source: Int] = [:]

    // Non-observed collaborators.
    @ObservationIgnored private let claudeReader = ClaudeUsageReader()
    @ObservationIgnored private let codexReader = CodexUsageReader()
    @ObservationIgnored private let claudeAPI = ClaudeUsageAPI()
    @ObservationIgnored private let codexRateLimit = CodexRateLimitReader()
    @ObservationIgnored private let healthChecker = HealthChecker()
    @ObservationIgnored private let advisor = Advisor()
    @ObservationIgnored private let pricing = Pricing.loadBundled()
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let scanQueue = DispatchQueue(label: "tokenmaster.scan")

    private let retention: TimeInterval = 7 * 86_400
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastUsageFetch: Date?
    private let usageMinInterval: TimeInterval = 60  // the usage API is rate-limited

    // MARK: Lifecycle

    init() {
        start()
    }

    func start() {
        guard !started else { return }
        started = true

        refresh()
        updateHealthAndAdvice()

        let home = FileManager.default.homeDirectoryForCurrentUser
        watcher = FileWatcher(paths: [
            home.appendingPathComponent(".claude/projects").path,
            home.appendingPathComponent(".codex/sessions").path
        ]) { [weak self] in self?.refresh() }
        watcher?.start()

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.updateHealthAndAdvice()
            }
        }
    }

    // MARK: Refresh

    func refresh() {
        let c = claudeReader, x = codexReader
        let api = claudeAPI, crl = codexRateLimit
        // Throttle the rate-limited Claude usage API; Codex is a cheap local read.
        let doClaudeUsage = lastUsageFetch == nil
            || Date().timeIntervalSince(lastUsageFetch!) >= usageMinInterval
        if doClaudeUsage { lastUsageFetch = Date() }

        scanQueue.async {
            let fresh = c.scan() + x.scan()
            let claudeReal = doClaudeUsage ? api.fetch() : nil
            let codexReal = crl.fetch()
            DispatchQueue.main.async {
                self.ingest(fresh)
                // Keep last good value if a cycle is skipped or fails transiently.
                if let claudeReal, claudeReal.live || self.claudeUsage.fiveHour == nil {
                    self.claudeUsage = claudeReal
                }
                if codexReal.live || self.codexUsage.fiveHour == nil {
                    self.codexUsage = codexReal
                }
            }
        }
    }

    private func ingest(_ fresh: [UsageEvent]) {
        for e in fresh {
            allTimeTokens[e.source, default: 0] += e.total
        }
        events.append(contentsOf: fresh)
        let cutoff = Date().addingTimeInterval(-retention)
        events.removeAll { $0.timestamp < cutoff }
        events.sort { $0.timestamp < $1.timestamp }
        lastRefresh = Date()
    }

    func updateHealthAndAdvice() {
        health = healthChecker.check()
        recommendations = advisor.recommendations(for: self)
    }

    // MARK: Windowed queries

    func events(source: UsageEvent.Source? = nil, since: Date) -> [UsageEvent] {
        events.filter { $0.timestamp >= since && (source == nil || $0.source == source!) }
    }

    func tokens(source: UsageEvent.Source? = nil, since: Date) -> Int {
        events(source: source, since: since).reduce(0) { $0 + $1.total }
    }

    var window5hTokens: Int {
        tokens(since: Date().addingTimeInterval(-ResetEstimator.fiveHours))
    }
    var todayTokens: Int {
        tokens(since: Calendar.current.startOfDay(for: Date()))
    }
    var last7dTokens: Int { tokens(since: Date().addingTimeInterval(-retention)) }

    func window5hTokens(source: UsageEvent.Source) -> Int {
        tokens(source: source, since: Date().addingTimeInterval(-ResetEstimator.fiveHours))
    }

    /// Cache-read share of all input over the last 7 days (0…1).
    var cacheHitRatio: Double {
        let seven = events(since: Date().addingTimeInterval(-retention))
        let read = seven.reduce(0) { $0 + $1.cacheRead }
        let inTotal = seven.reduce(0) { $0 + $1.input + $1.cacheCreate + $1.cacheRead }
        return inTotal == 0 ? 0 : Double(read) / Double(inTotal)
    }

    /// Thinking share of output over the last 7 days (0…1).
    var thinkingShare: Double {
        let seven = events(since: Date().addingTimeInterval(-retention))
        let out = seven.reduce(0) { $0 + $1.output }
        let think = seven.reduce(0) { $0 + $1.thinking }
        return out == 0 ? 0 : Double(think) / Double(out)
    }

    // MARK: Cost

    var costAvailable: Bool { pricing != nil }

    func cost7d(source: UsageEvent.Source? = nil) -> Double? {
        guard let pricing else { return nil }
        return pricing.cost(of: events(source: source, since: Date().addingTimeInterval(-retention)))
    }

    // MARK: Real usage (accurate source; drives the colored meters)

    func providerUsage(_ source: UsageEvent.Source) -> ProviderUsage {
        source == .claude ? claudeUsage : codexUsage
    }

    /// Provider-reported 5h utilization percent (0…100+), nil if unavailable.
    func utilization(_ source: UsageEvent.Source) -> Double? {
        providerUsage(source).fiveHour?.utilization
    }

    /// True when the number is the provider's own (not a token-budget fallback).
    func isLive(_ source: UsageEvent.Source) -> Bool {
        providerUsage(source).fiveHour != nil
    }

    func budget(_ source: UsageEvent.Source) -> Int { Prefs.shared.budget(for: source) }

    /// Fallback only: token consumption vs budget, unclamped.
    func ratio(_ source: UsageEvent.Source) -> Double {
        let b = budget(source)
        guard b > 0 else { return 0 }
        return Double(window5hTokens(source: source)) / Double(b)
    }

    /// Ring-fill fraction 0…1 — real utilization if available, else budget ratio.
    func fraction(_ source: UsageEvent.Source) -> Double {
        if let u = utilization(source) { return min(1.0, max(0.0, u / 100.0)) }
        return min(1.0, max(0.0, ratio(source)))
    }

    /// Percent label — real utilization (can read >100) or fallback fraction.
    func percentText(_ source: UsageEvent.Source) -> String {
        if let u = utilization(source) { return "\(Int(u.rounded()))%" }
        return Format.percent(fraction(source))
    }

    func status(_ source: UsageEvent.Source) -> UsageStatus {
        let f = utilization(source).map { $0 / 100.0 } ?? ratio(source)
        if f >= Prefs.shared.dangerThreshold { return .danger }
        if f >= Prefs.shared.cautionThreshold { return .caution }
        return .ok
    }

    // MARK: Reset (real timestamp if provider gave one, else local estimate)

    func nextReset(_ source: UsageEvent.Source) -> Date? {
        if let real = providerUsage(source).fiveHour?.resetsAt { return real }
        return ResetEstimator.nextReset(
            events: events.filter { $0.source == source },
            window: ResetEstimator.fiveHours)
    }

    func sevenDayUtilization(_ source: UsageEvent.Source) -> Double? {
        providerUsage(source).sevenDay?.utilization
    }

    // MARK: Session counting + averages (for savings estimates)

    private func sessionRoot(_ source: UsageEvent.Source) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch source {
        case .claude: return home.appendingPathComponent(".claude/projects")
        case .codex:  return home.appendingPathComponent(".codex/sessions")
        }
    }

    /// Number of session log files created since `date` — a proxy for "sessions run".
    func sessionsSince(_ source: UsageEvent.Source, _ date: Date) -> Int {
        let root = sessionRoot(source)
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true }
        ) else { return 0 }
        var count = 0
        for case let url as URL in en where url.pathExtension == "jsonl" {
            if let c = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
               c > date { count += 1 }
        }
        return count
    }

    func avgTokensPerSession(_ source: UsageEvent.Source) -> Int {
        let weekAgo = Date().addingTimeInterval(-retention)
        let sessions = max(1, sessionsSince(source, weekAgo))
        return tokens(source: source, since: weekAgo) / sessions
    }

    func avgOutputPerSession(_ source: UsageEvent.Source) -> Int {
        let weekAgo = Date().addingTimeInterval(-retention)
        let sessions = max(1, sessionsSince(source, weekAgo))
        let out = events(source: source, since: weekAgo).reduce(0) { $0 + $1.output }
        return out / sessions
    }

    func inputRate(_ source: UsageEvent.Source) -> Double? {
        pricing?.inputRate(for: source)
    }

    // MARK: Menu-bar text (fallback / accessibility)

    var menuBarLabel: String {
        "🪙 " + Format.compact(window5hTokens)
    }
}

enum Format {
    static func compact(_ n: Int) -> String {
        switch n {
        case 1_000_000...:
            return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fk", Double(n) / 1_000)
        default:
            return "\(n)"
        }
    }

    static func usd(_ v: Double) -> String {
        v >= 10 ? String(format: "$%.0f", v) : String(format: "$%.2f", v)
    }

    static func percent(_ v: Double) -> String {
        String(format: "%.0f%%", v * 100)
    }
}
