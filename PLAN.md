# TOKEN MASTER — Mac menu-bar token meter + optimizer

## Context
Roberto (Apple developer) runs Claude Code and Codex/ChatGPT heavily and wants a
"right-hand man": a Mac app that launches at login, lives in the menu bar, measures
LLM **token usage** in real time, estimates the next usage-reset window, verifies both
tools are logged in and healthy, and recommends (opt-in, one-click) config changes that
cut token burn. Ships free.

**Feasibility confirmed by probing local data (read-only):**
- Claude Code: `~/.claude/projects/**/*.jsonl` — every turn logs full `usage`
  (`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`,
  `output_tokens`, `output_tokens_details.thinking_tokens`). Also `~/.claude/stats-cache.json`.
- Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` — carry `total_token_usage`
  (`input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_output_tokens`, `total_tokens`).
- Health: Keychain item `Claude Code-credentials` exists (Claude auth); Codex auth in `~/.codex/config.toml`.

**Decisions (user-approved):** Direct-download Developer ID / notarized (App Store later — sandbox
blocks reading these dirs) · Advisor + opt-in one-click fixes (never autonomous) · Build a working
v1 THIS session · Reset window = computed locally, labelled "estimate".

**Scope reality:** v1 = a working, native, local-run menu-bar app this session, plus GitHub repo and
Desktop/TOKEN MASTER folder. Code-signing, notarization, DMG, and App Store are a documented **phase 2**,
not this session.

## Why Xcode/SwiftUI
Yes — native menu-bar Mac app = Xcode + SwiftUI `MenuBarExtra` (macOS 13+), `LSUIElement` (no dock icon).
Non-sandboxed Developer ID build reads dot-dirs in the user's own home without Full Disk Access; if a
future protected path needs it, prompt the user to grant FDA.

## Architecture (v1)
Single Xcode app target `TokenMaster`, `LSUIElement=YES`, SwiftUI lifecycle. Modules:

- **Readers** (`Readers/`)
  - `ClaudeUsageReader.swift` — enumerate `~/.claude/projects/**/*.jsonl`, parse each line's `usage`,
    key by message timestamp; track per-file byte offset so only new lines are re-parsed.
  - `CodexUsageReader.swift` — enumerate `~/.codex/sessions/**/rollout-*.jsonl`, parse `total_token_usage`;
    same incremental-offset approach.
  - Common `UsageEvent` model: `{source, timestamp, input, cacheCreate, cacheRead, output, thinking}`.
- **Watcher** (`Watch/FileWatcher.swift`) — FSEvents/`DispatchSource` on both dirs → debounced refresh.
- **Aggregator** (`Model/UsageStore.swift`) — rolling windows (5h rolling, 7d rolling, today, all-time),
  per-source split, cache-hit ratio, thinking share, optional cost estimate from a bundled
  `pricing.json` (fill current model prices via the `claude-api` skill; cost hidden if prices absent).
- **Health** (`Health/HealthChecker.swift`) — Claude: Keychain `Claude Code-credentials` present +
  parse expiry, `claude` on PATH, recent JSONL activity. Codex: auth present in config.toml, recent
  rollout activity. Emits red/amber/green per tool.
- **Reset estimator** (`Model/ResetEstimator.swift`) — from oldest event still inside each rolling
  window + window length → approximate next-reset countdown; UI labels it "estimate".
- **Advisor** (`Advisor/`) — `Rule` protocol → `[Recommendation]` each with `title`, `rationale`,
  `estimatedSaving`, optional `apply()`. v1 rules: route mechanical work to Haiku; `/clear` vs
  `/compact`; compress oversized `CLAUDE.md`/`MEMORY.md`; prune large stale context files; ensure prompt
  caching; suggest caveman mode. `apply()` always backs up the file first and asks for confirmation.
- **UI** (`UI/`) — `MenuBarExtra` label = live number (tokens in current window or % of window);
  popover: token meter + window breakdown, two health lights, "next reset (est.)" countdown,
  recommendations list with per-item **Apply** buttons, and footer links (repo, refresh, quit).
- **Launch at login** — `SMAppService.mainApp.register()` toggle in a small Settings scene.

## Data flow
FileWatcher → Readers (incremental) → UsageStore (aggregate + windows) → SwiftUI observes via
`@Observable`/Combine → MenuBar label + popover. HealthChecker + ResetEstimator run on a timer
(e.g. 30–60s) and on file change. Advisor recomputes from UsageStore + scanned config files.

## Error handling
All disk reads tolerate missing/locked/partial files (skip line, keep going). If a dir is unreadable,
show amber health with a "Grant access" hint (opens System Settings → Privacy). Malformed JSON lines
skipped, not fatal. Every advisor `apply()` writes a `.bak` and is reversible.

## Deliverables & locations
- `~/Desktop/TOKEN MASTER/` — Xcode project + `README.md` + `docs/` (design, phase-2 notarization steps).
- GitHub repo `TOKEN-MASTER` (via `gh repo create`, public, free), pushed from that folder,
  with `.gitignore` (build products, DerivedData, `pricing.json` if it holds anything private).
- Commits end with the session's Co-Authored-By / Claude-Session trailer.

## Critical files to create
- `TokenMaster.xcodeproj` (or SwiftPM-generated project)
- `App/TokenMasterApp.swift`, `UI/MenuView.swift`, `UI/SettingsView.swift`
- `Readers/ClaudeUsageReader.swift`, `Readers/CodexUsageReader.swift`
- `Model/UsageStore.swift`, `Model/UsageEvent.swift`, `Model/ResetEstimator.swift`
- `Watch/FileWatcher.swift`, `Health/HealthChecker.swift`
- `Advisor/Advisor.swift`, `Advisor/Rules/*.swift`, `Resources/pricing.json`
- `README.md`, `docs/2026-09-16-token-master-design.md`, `docs/phase2-notarization.md`

## Foreseen issues + solutions (pre-solved)
- **Sandbox vs read access** → ship non-sandboxed Developer ID (decided); App Store deferred.
- **Log volume / re-parse cost** → incremental byte-offset reads + FSEvents, never full rescans.
- **Reset time not in logs** → local rolling-window estimate, clearly labelled.
- **Codex/Claude change log format** → readers defensive; unknown keys ignored; version-tag parsers.
- **Keychain prompt spam on health check** → read-only existence/metadata check, cache result, no secret extraction.
- **Advisor breaking configs** → opt-in only, `.bak` before every write, undo.
- **"Optimize" over-promise** → framed as meter + advisor, honest `estimatedSaving`, no magic.
- **Multi-machine / future Windows** → readers isolated behind a `UsageSource` protocol so a Windows
  port (phase 3) swaps only path logic.

## Verification (end-to-end this session)
1. `xcodebuild -scheme TokenMaster build` succeeds (or Run in Xcode).
2. Launch app → menu-bar item appears, no dock icon.
3. Popover shows non-zero Claude token totals (cross-check against a `grep '"usage"'` sum from a
   known JSONL) and Codex totals; window breakdown populates.
4. Toggle launch-at-login → confirm `SMAppService` status registered.
5. Health lights: Claude green (Keychain item present), Codex reflects config.toml state.
6. Trigger a new Claude Code turn → within seconds the live counter increments (watcher works).
7. Recommendations list renders ≥1 item; an Apply writes a `.bak` and is reversible.
8. `~/Desktop/TOKEN MASTER/` exists, `git log` shows commits, `gh repo view` shows the pushed repo.

## Phase 2 (documented, not this session)
Developer ID signing, `notarytool` notarization, stapled DMG, Sparkle auto-update, then App Store
sandbox-helper investigation. Steps captured in `docs/phase2-notarization.md`.
