# TOKEN MASTER — design notes (2026-09-16)

## Goal
Menu-bar Mac app that measures LLM token usage in real time, estimates the next
usage-reset window, verifies Claude Code + Codex are logged in and healthy, and
recommends (opt-in) config changes that cut token burn. Ships free, runs locally.

## Feasibility (verified by read-only probing)
- **Claude Code** logs every turn's `usage` in `~/.claude/projects/**/*.jsonl`
  (`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`,
  `output_tokens`, `output_tokens_details.thinking_tokens`), with a top-level ISO
  `timestamp`.
- **Codex** rollout files `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` carry a
  cumulative `total_token_usage` (`input_tokens`, `cached_input_tokens`,
  `output_tokens`, `reasoning_output_tokens`, `total_tokens`).
- **Health**: Keychain generic-password item `Claude Code-credentials` (Claude
  auth); Codex auth in `~/.codex` (`auth.json` / `config.toml`).

## Key decisions
- **Distribution**: non-sandboxed Developer ID / notarized (direct download). The
  App Store sandbox blocks reading these dot-dirs, so App Store is deferred.
- **Advisor**: recommend + one-click apply, **never autonomous**; `.bak` before
  every write; reversible.
- **Reset window**: computed locally from the rolling window's oldest live event,
  always labelled "estimate" — the logs don't contain the real reset time.

## Normalized model
`UsageEvent { source, timestamp, input, cacheCreate, cacheRead, output, thinking }`.
Claude maps directly. Codex is cumulative per session, so consecutive snapshots per
file are **diffed** into per-turn events (fresh input = `input − cached`,
`cacheRead = cached`, `thinking = reasoning_output_tokens`).

## Aggregation
`UsageStore` (@MainActor, @Observable) keeps a 7-day rolling buffer plus all-time
accumulators. Windows: current 5h, today, 7d. Derived: per-source split, cache-hit
ratio, thinking share, cost (from `pricing.json`, hidden if absent).

## Data flow
`FileWatcher` (FSEvents on both roots, debounced) + a 30s timer → readers'
incremental `scan()` (per-file byte offsets, no rescans) → `UsageStore.ingest` on
the main actor → SwiftUI `MenuBarExtra` label + popover. `HealthChecker` and the
`Advisor` recompute on refresh.

## Reliability
All disk reads tolerate missing/locked/partial files — malformed JSON lines are
skipped, never fatal. File truncation/rotation resets the byte offset. Keychain
check reads attributes only (no data) to avoid auth prompts.

## Verification performed this session
- `xcodebuild … build` → **BUILD SUCCEEDED**, no warnings.
- App launches as a background agent (`LSUIElement`), no dock icon, 🪙 menu label.
- Reader math cross-checked against an independent `jq`/Python sum of the JSONL:
  last-5h Claude total matched (~11.4M tokens / 141 turns at build time).
- Advisor renders recommendations; the compress-config rule's Apply writes a `.bak`.

## Known v1 limitations
- Cost uses a single per-source rate, not per-model. Edit `pricing.json`.
- Reset estimate is a rolling-window approximation, not the provider's real clock.
- Unsigned build → Gatekeeper warning until phase-2 notarization.
