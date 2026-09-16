import Foundation

/// One measured LLM turn's token usage, normalized across sources.
struct UsageEvent {
    enum Source: String, CaseIterable {
        case claude
        case codex

        var display: String {
            switch self {
            case .claude: return "Claude"
            case .codex:  return "Codex"
            }
        }
    }

    let source: Source
    let timestamp: Date
    let input: Int        // fresh (uncached) input tokens
    let cacheCreate: Int  // tokens written to prompt cache
    let cacheRead: Int    // tokens served from prompt cache
    let output: Int       // generated tokens (includes thinking)
    let thinking: Int     // reasoning/thinking tokens (subset of output)

    /// All billed token movement for this turn.
    var total: Int { input + cacheCreate + cacheRead + output }
}
