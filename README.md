# TOKEN MASTER

A native macOS menu-bar app that meters your **LLM token usage** in real time and
helps you cut it. Built for people who run **Claude Code** and **Codex/ChatGPT**
heavily and want a right-hand man in the menu bar.

- **Live meter** — tokens used in the current rolling 5-hour window, updating within
  seconds as you work (FSEvents + timer).
- **Windows** — today, last 7 days, per-source (Claude vs Codex) split, cache-hit
  ratio, thinking share, and optional cost estimate.
- **Health** — two lights: are Claude Code and Codex logged in and active?
- **Next reset (estimate)** — local rolling-window countdown, clearly labelled.
- **Advisor** — opt-in, one-click recommendations that cut token burn. Never
  autonomous; every file-touching action backs up first (`.bak`) and is reversible.

Everything runs locally. It reads only your own log files under `~/.claude` and
`~/.codex`; **nothing leaves your Mac.**

## How it works

| Source | Read from | Signal |
|--------|-----------|--------|
| Claude Code | `~/.claude/projects/**/*.jsonl` | each turn's `message.usage` |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl` | cumulative `total_token_usage`, diffed |

Readers are incremental (per-file byte offsets) — no full rescans. Health uses a
read-only Keychain existence check (no secret extraction, no prompt spam).

## Architecture

```
FileWatcher (FSEvents) ─┐
timer (30s) ────────────┼─► Readers (incremental) ─► UsageStore (@Observable)
                        │        ClaudeUsageReader          rolling windows
                        │        CodexUsageReader           per-source, cost
                        │                                        │
HealthChecker ──────────┘                                        ▼
Advisor (Rules ─► [Recommendation])                     MenuBarExtra + popover
```

Source layout under `Sources/`: `App/`, `UI/`, `Readers/`, `Model/`, `Watch/`,
`Health/`, `Advisor/Rules/`, `Resources/pricing.json`.

## Build & run

Requires Xcode 14+ (SwiftUI `MenuBarExtra`, macOS 14+ target).

```sh
brew install xcodegen        # once
xcodegen generate            # produces TokenMaster.xcodeproj
open TokenMaster.xcodeproj   # ⌘R in Xcode
```

Or from the CLI (if `xcode-select` points at full Xcode):

```sh
xcodebuild -project TokenMaster.xcodeproj -scheme TokenMaster build
```

The app has no dock icon (`LSUIElement`); look for the 🪙 counter in the menu bar.

## Cost estimates

`Sources/Resources/pricing.json` holds USD-per-1M-token rates. Edit it to match
your plan; if a source has no rate, its cost is simply hidden. Defaults: Claude
Opus-tier $5 in / $25 out; Codex a GPT-5-class estimate — **verify and adjust.**

## Advisor rules (v1)

- Low prompt-cache hit rate
- High thinking share → route mechanical work to Haiku
- Heavy current window → `/clear` between jobs (not `/compact`)
- Oversized `CLAUDE.md` / `MEMORY.md` → back up, then compress *(has Apply)*
- High output volume → try caveman mode

## Status

v1: working local menu-bar app. **Phase 2** (code signing, notarization, DMG,
Sparkle auto-update, App Store investigation) is documented in
[`docs/phase2-notarization.md`](docs/phase2-notarization.md) and not yet done —
so macOS Gatekeeper will warn on first launch of an unsigned build.

## License

Free. Personal project.
