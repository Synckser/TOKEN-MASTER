import Foundation
import Observation

/// Rough token estimate for a text config file (~4 chars/token).
enum TokenEstimate {
    static func ofFile(_ path: String) -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int else { return 0 }
        return size / 4
    }
}

/// One applied optimization, persisted so its savings keep accruing across launches.
struct LedgerEntry: Codable, Identifiable {
    enum Kind: String, Codable {
        case fileDelta    // saves (baseline − current file tokens) every session it's re-sent
        case oneTime      // saves a fixed amount once (e.g. a pruned file)
        case perSession   // saves an estimated amount each session (behavioral change)
    }

    var id: String            // == optimization id (one active entry per optimization)
    var source: String        // UsageEvent.Source.rawValue
    var title: String
    var appliedAt: Date
    var kind: Kind
    var amountTokens: Int      // baseline (fileDelta), or the saved amount (oneTime/perSession)
    var path: String?          // fileDelta: file whose current size we re-measure
    var backupPath: String?    // for undo/restore
}

/// Durable store of applied optimizations + the cumulative savings they represent.
@Observable
final class SavingsLedger {
    static let shared = SavingsLedger()

    private(set) var entries: [LedgerEntry] = []

    @ObservationIgnored private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TokenMaster", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("savings.json")
    }()

    private init() { load() }

    func entry(id: String) -> LedgerEntry? { entries.first { $0.id == id } }
    func isApplied(_ id: String) -> Bool { entry(id: id) != nil }

    func add(_ e: LedgerEntry) {
        entries.removeAll { $0.id == e.id }
        entries.append(e)
        save()
    }

    func remove(id: String) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Tokens saved by one entry, given how many sessions have run since it applied.
    func savedTokens(_ e: LedgerEntry, sessionsSince: Int) -> Int {
        switch e.kind {
        case .fileDelta:
            let current = e.path.map { TokenEstimate.ofFile($0) } ?? 0
            return max(0, e.amountTokens - current) * max(0, sessionsSince)
        case .oneTime:
            return e.amountTokens
        case .perSession:
            return e.amountTokens * max(0, sessionsSince)
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        entries = (try? dec.decode([LedgerEntry].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(entries) { try? data.write(to: url) }
    }
}
