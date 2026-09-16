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

    // All-time accumulators (survive event pruning; reset per launch).
    private(set) var allTimeTokens: [UsageEvent.Source: Int] = [:]

    // Non-observed collaborators.
    @ObservationIgnored private let claudeReader = ClaudeUsageReader()
    @ObservationIgnored private let codexReader = CodexUsageReader()
    @ObservationIgnored private let healthChecker = HealthChecker()
    @ObservationIgnored private let advisor = Advisor()
    @ObservationIgnored private let pricing = Pricing.loadBundled()
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let scanQueue = DispatchQueue(label: "tokenmaster.scan")

    private let retention: TimeInterval = 7 * 86_400

    // MARK: Lifecycle

    func start() {
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
        scanQueue.async {
            let fresh = c.scan() + x.scan()
            DispatchQueue.main.async { self.ingest(fresh) }
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

    // MARK: Reset estimate

    var nextClaudeReset: Date? {
        ResetEstimator.nextReset(
            events: events.filter { $0.source == .claude },
            window: ResetEstimator.fiveHours)
    }

    // MARK: Menu-bar label

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
