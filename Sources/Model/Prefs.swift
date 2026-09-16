import Foundation
import Observation

/// User-editable preferences, persisted to UserDefaults. Single shared instance so
/// the menu-bar label, popover, and Settings all observe the same values.
@Observable
final class Prefs {
    static let shared = Prefs()

    /// Per-5h-window token budget the meter fills toward, per source.
    var claudeBudget5h: Int { didSet { d.set(claudeBudget5h, forKey: "claudeBudget5h") } }
    var codexBudget5h: Int  { didSet { d.set(codexBudget5h, forKey: "codexBudget5h") } }

    /// Fraction of budget where green turns blue (caution) and blue turns red (danger).
    var cautionThreshold: Double { didSet { d.set(cautionThreshold, forKey: "cautionThreshold") } }
    var dangerThreshold: Double  { didSet { d.set(dangerThreshold, forKey: "dangerThreshold") } }

    @ObservationIgnored private let d = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard
        claudeBudget5h   = d.object(forKey: "claudeBudget5h") as? Int ?? 15_000_000
        codexBudget5h    = d.object(forKey: "codexBudget5h") as? Int ?? 5_000_000
        cautionThreshold = d.object(forKey: "cautionThreshold") as? Double ?? 0.60
        dangerThreshold  = d.object(forKey: "dangerThreshold") as? Double ?? 0.85
    }

    func budget(for source: UsageEvent.Source) -> Int {
        switch source {
        case .claude: return claudeBudget5h
        case .codex:  return codexBudget5h
        }
    }
}
