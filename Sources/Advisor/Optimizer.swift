import Foundation

/// A concrete, per-source optimization the user can apply (and undo) to cut tokens.
struct Optimization: Identifiable {
    enum Action { case fileApply, behavioral }
    let id: String
    let source: UsageEvent.Source
    let title: String
    let why: String
    let saving: String          // human estimate badge
    let cite: String            // short source attribution
    let action: Action
    let available: Bool
    /// Performs the change (backs up first when it touches a file) and returns the
    /// ledger entry to record. Behavioral ones just start tracking an estimate.
    let perform: () throws -> LedgerEntry
    /// Undo/restore. nil = simply drop the ledger entry.
    let revert: ((LedgerEntry) throws -> Void)?
}

/// Builds the Claude and Codex optimization catalogs and applies/undoes them,
/// keeping the SavingsLedger in sync.
@MainActor
final class Optimizer {
    let store: UsageStore
    let ledger = SavingsLedger.shared
    private let fm = FileManager.default
    private var home: URL { fm.homeDirectoryForCurrentUser }

    init(store: UsageStore) { self.store = store }

    func optimizations(for source: UsageEvent.Source) -> [Optimization] {
        source == .claude ? claudeCatalog() : codexCatalog()
    }

    // MARK: Apply / undo

    func apply(_ opt: Optimization) throws {
        let entry = try opt.perform()
        ledger.add(entry)
    }

    func undo(_ opt: Optimization) throws {
        guard let entry = ledger.entry(id: opt.id) else { return }
        try opt.revert?(entry)
        ledger.remove(id: opt.id)
    }

    // MARK: Savings

    func savedTokens(for source: UsageEvent.Source) -> Int {
        ledger.entries
            .filter { $0.source == source.rawValue }
            .reduce(0) { sum, e in
                sum + ledger.savedTokens(e, sessionsSince: store.sessionsSince(source, e.appliedAt))
            }
    }

    func savedTokens(entryFor opt: Optimization) -> Int {
        guard let e = ledger.entry(id: opt.id) else { return 0 }
        return ledger.savedTokens(e, sessionsSince: store.sessionsSince(opt.source, e.appliedAt))
    }

    func savedCost(for source: UsageEvent.Source) -> Double? {
        guard let rate = store.inputRate(source) else { return nil }
        return Double(savedTokens(for: source)) / 1_000_000 * rate
    }

    func totalSavedTokens() -> Int { savedTokens(for: .claude) + savedTokens(for: .codex) }

    // MARK: Claude catalog

    private func claudeCatalog() -> [Optimization] {
        var list: [Optimization] = []
        let mdURL = home.appendingPathComponent(".claude/CLAUDE.md")
        let mdTokens = TokenEstimate.ofFile(mdURL.path)

        // 1. Compress global CLAUDE.md (re-sent every session).
        list.append(Optimization(
            id: "claude.compress_claude_md",
            source: .claude,
            title: "Compress global CLAUDE.md",
            why: "CLAUDE.md loads into every session. 300–500 words is ideal; yours is ~\(mdTokens) tokens. Backs it up (.bak), then shrink it (e.g. /caveman:compress) — savings accrue as it gets smaller.",
            saving: "500–2,000 tok/session",
            cite: "StationX · LowCode 2026",
            action: .fileApply,
            available: mdTokens > 1000,
            perform: {
                let bak = try Advisor.backup(mdURL)
                return LedgerEntry(id: "claude.compress_claude_md", source: "claude",
                                   title: "Compress CLAUDE.md", appliedAt: Date(),
                                   kind: .fileDelta, amountTokens: TokenEstimate.ofFile(mdURL.path),
                                   path: mdURL.path, backupPath: bak.path)
            },
            revert: { e in if let b = e.backupPath { try? self.fm.removeItem(atPath: b) } }
        ))

        // 2. Prune a stale, large context file.
        if let stale = largestStale(in: home.appendingPathComponent(".claude/projects"),
                                    olderThanDays: 14, minBytes: 200_000) {
            let toks = TokenEstimate.ofFile(stale.path)
            list.append(Optimization(
                id: "claude.prune_stale",
                source: .claude,
                title: "Archive stale context file",
                why: "\(stale.lastPathComponent) (~\(toks) tokens) hasn't changed in >14 days. Archiving it (to .bak) trims what gets scanned. Reversible.",
                saving: "\(Format.compact(toks)) tok",
                cite: "Anthropic context engineering",
                action: .fileApply,
                available: true,
                perform: {
                    let bak = stale.path + ".bak"
                    try? self.fm.removeItem(atPath: bak)
                    try self.fm.moveItem(atPath: stale.path, toPath: bak)
                    return LedgerEntry(id: "claude.prune_stale", source: "claude",
                                       title: "Archive \(stale.lastPathComponent)", appliedAt: Date(),
                                       kind: .oneTime, amountTokens: toks, path: nil, backupPath: bak)
                },
                revert: { e in
                    if let b = e.backupPath { try self.fm.moveItem(atPath: b, toPath: String(b.dropLast(4))) }
                }
            ))
        }

        let avg = store.avgTokensPerSession(.claude)
        let avgOut = store.avgOutputPerSession(.claude)

        // 3. Prompt caching.
        list.append(behavioral(
            id: "claude.prompt_caching", source: .claude,
            title: "Improve prompt caching",
            why: "Cache hit rate is \(Format.percent(store.cacheHitRatio)). Cached reads cost ~10% of fresh input — keep the system prompt & tool list stable so the prefix stays cached.",
            saving: "up to 90% off resends", cite: "Anthropic · hidekazu-konishi",
            available: store.cacheHitRatio < 0.5 && store.last7dTokens > 50_000,
            perSession: Int(0.30 * Double(avg))))

        // 4. Route mechanical work to Haiku.
        list.append(behavioral(
            id: "claude.route_haiku", source: .claude,
            title: "Route mechanical work to Haiku",
            why: "Thinking is \(Format.percent(store.thinkingShare)) of output. Send bulk/mechanical work to a Haiku subagent and keep Opus for architecture & debugging.",
            saving: "Haiku ≈ 1/5 Opus price", cite: "Sonnet-default routing 2026",
            available: store.thinkingShare > 0.30 || store.last7dTokens > 1_000_000,
            perSession: Int(0.30 * Double(avg))))

        // 5. /clear vs /compact discipline.
        list.append(behavioral(
            id: "claude.clear_compact", source: .claude,
            title: "Use /clear between unrelated jobs",
            why: "You moved \(Format.compact(store.window5hTokens)) tokens in the last 5h. /clear resets context between tasks; /compact re-summarises (and re-bills) history.",
            saving: "avoids re-summarising", cite: "Claude Code docs",
            available: store.window5hTokens > 150_000,
            perSession: Int(0.20 * Double(avg))))

        // 6. Trim MCP tool bloat.
        let mcpClaude = fileContains(home.appendingPathComponent(".claude.json"), "mcpServers")
            || fileContains(home.appendingPathComponent(".claude/settings.json"), "mcpServers")
        list.append(behavioral(
            id: "claude.trim_mcp", source: .claude,
            title: "Trim MCP tool bloat",
            why: "Each enabled MCP server's tool schemas are sent every turn — a big one can add ~55k tokens before you type. Disable servers you use rarely.",
            saving: "~20k+ tok/turn", cite: "danielvaughan Codex KB",
            available: mcpClaude,
            perSession: 20_000))

        // 7. Terser output (caveman).
        list.append(behavioral(
            id: "claude.caveman", source: .claude,
            title: "Terser output (caveman mode)",
            why: "~\(Format.compact(avgOut)) output tokens/session. Caveman mode drops filler and cuts output ~75% while keeping technical substance.",
            saving: "~75% fewer output tok", cite: "caveman skill",
            available: avgOut > 20_000,
            perSession: Int(0.50 * Double(avgOut))))

        return list
    }

    // MARK: Codex catalog

    private func codexCatalog() -> [Optimization] {
        var list: [Optimization] = []
        let cfg = home.appendingPathComponent(".codex/config.toml")
        let effort = codexEffort(cfg)
        let avgOut = store.avgOutputPerSession(.codex)
        let avg = store.avgTokensPerSession(.codex)

        // 1. Lower reasoning effort → low.
        list.append(Optimization(
            id: "codex.effort_low",
            source: .codex,
            title: "Lower reasoning effort to low",
            why: "Current: \(effort ?? "default"). Dropping medium→low saves 40–60% on routine work (scaffolding, formatting, tests). Reasoning tokens count but aren't shown. Backs up config.toml.",
            saving: "40–60% on routine", cite: "danielvaughan Codex KB",
            action: .fileApply,
            available: (effort ?? "medium") != "low" && (effort ?? "") != "minimal",
            perform: {
                let bak = try Advisor.backup(cfg)
                try self.setCodexEffort(cfg, to: "low")
                return LedgerEntry(id: "codex.effort_low", source: "codex",
                                   title: "Reasoning effort → low", appliedAt: Date(),
                                   kind: .perSession, amountTokens: Int(0.40 * Double(max(avgOut, 5_000))),
                                   path: nil, backupPath: bak.path)
            },
            revert: { e in
                if let b = e.backupPath {
                    try? self.fm.removeItem(at: cfg)
                    try self.fm.copyItem(atPath: b, toPath: cfg.path)
                    try? self.fm.removeItem(atPath: b)
                }
            }
        ))

        // 2. Smaller model for simple tasks.
        list.append(behavioral(
            id: "codex.smaller_model", source: .codex,
            title: "Use a smaller model for simple tasks",
            why: "Reserve the top model for hard problems; switch to a smaller/faster model for routine edits and Q&A to cut per-token cost.",
            saving: "lower $/token", cite: "OpenAI community 2026",
            available: avg > 50_000,
            perSession: Int(0.25 * Double(avg))))

        // 3. Trim MCP servers.
        let mcpCodex = fileContains(cfg, "mcp_servers")
        list.append(behavioral(
            id: "codex.trim_mcp", source: .codex,
            title: "Trim MCP servers",
            why: "A GitHub MCP server exposing 93 tools can add ~55k tokens per turn. Run /status, disable servers you rarely use.",
            saving: "~55k tok/turn", cite: "danielvaughan Codex KB",
            available: mcpCodex,
            perSession: 30_000))

        // 4. Lower verbosity.
        list.append(behavioral(
            id: "codex.verbosity", source: .codex,
            title: "Lower verbosity",
            why: "Terser responses save output tokens without hurting code quality.",
            saving: "fewer output tok", cite: "danielvaughan Codex KB",
            available: avgOut > 15_000,
            perSession: Int(0.20 * Double(avgOut))))

        // 5. Clear bloated sessions.
        list.append(behavioral(
            id: "codex.clear_session", source: .codex,
            title: "Clear bloated sessions",
            why: "Long sessions resend a growing transcript each turn. Start a fresh session at natural stopping points.",
            saving: "avoids transcript resend", cite: "Inventive HQ",
            available: (store.utilization(.codex) ?? 0) > 40 || avg > 80_000,
            perSession: Int(0.20 * Double(avg))))

        return list
    }

    // MARK: Helpers

    private func behavioral(id: String, source: UsageEvent.Source, title: String, why: String,
                            saving: String, cite: String, available: Bool, perSession: Int) -> Optimization {
        Optimization(
            id: id, source: source, title: title, why: why, saving: saving, cite: cite,
            action: .behavioral, available: available,
            perform: {
                LedgerEntry(id: id, source: source.rawValue, title: title, appliedAt: Date(),
                            kind: .perSession, amountTokens: max(0, perSession),
                            path: nil, backupPath: nil)
            },
            revert: nil)
    }

    private func fileContains(_ url: URL, _ needle: String) -> Bool {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return s.contains(needle)
    }

    private func largestStale(in root: URL, olderThanDays: Int, minBytes: Int) -> URL? {
        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 86_400)
        guard let en = fm.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles], errorHandler: { _, _ in true }
        ) else { return nil }
        var best: (URL, Int)?
        for case let url as URL in en where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let size = v.fileSize, size >= minBytes,
                  let mod = v.contentModificationDate, mod < cutoff else { continue }
            if best == nil || size > best!.1 { best = (url, size) }
        }
        return best?.0
    }

    private func codexEffort(_ cfg: URL) -> String? {
        guard let s = try? String(contentsOf: cfg, encoding: .utf8) else { return nil }
        for line in s.split(separator: "\n") where line.contains("model_reasoning_effort") {
            if let eq = line.firstIndex(of: "=") {
                return line[line.index(after: eq)...]
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'\t"))
            }
        }
        return nil
    }

    private func setCodexEffort(_ cfg: URL, to value: String) throws {
        let text = (try? String(contentsOf: cfg, encoding: .utf8)) ?? ""
        let newLine = "model_reasoning_effort = \"\(value)\""
        var out: [String] = []
        var replaced = false
        for raw in text.components(separatedBy: "\n") {
            if raw.contains("model_reasoning_effort") {
                out.append(newLine)
                replaced = true
            } else {
                out.append(raw)
            }
        }
        var result = out.joined(separator: "\n")
        if !replaced { result = newLine + "\n" + result }
        try result.write(to: cfg, atomically: true, encoding: .utf8)
    }
}
