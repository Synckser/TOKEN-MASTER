import Foundation

/// Per-source token prices (USD per 1M tokens), loaded from bundled pricing.json.
struct Pricing {
    struct Rate {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double
    }

    private let rates: [UsageEvent.Source: Rate]

    /// nil if no pricing available at all → cost UI hidden.
    static func loadBundled() -> Pricing? {
        guard let url = Bundle.main.url(forResource: "pricing", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var rates: [UsageEvent.Source: Rate] = [:]
        for source in UsageEvent.Source.allCases {
            guard let d = obj[source.rawValue] as? [String: Any] else { continue }
            func num(_ k: String) -> Double? { (d[k] as? NSNumber)?.doubleValue }
            guard let input = num("input"), let output = num("output") else { continue }
            rates[source] = Rate(
                input: input,
                output: output,
                cacheRead: num("cacheRead") ?? input * 0.1,
                cacheWrite: num("cacheWrite") ?? input * 1.25
            )
        }
        return rates.isEmpty ? nil : Pricing(rates: rates)
    }

    func hasRate(for source: UsageEvent.Source) -> Bool { rates[source] != nil }

    func inputRate(for source: UsageEvent.Source) -> Double? { rates[source]?.input }

    /// Cost in USD for one event's token movement.
    func cost(of e: UsageEvent) -> Double {
        guard let r = rates[e.source] else { return 0 }
        let m = 1.0 / 1_000_000.0
        let inCost = Double(e.input) * r.input
        let writeCost = Double(e.cacheCreate) * r.cacheWrite
        let readCost = Double(e.cacheRead) * r.cacheRead
        let outCost = Double(e.output) * r.output
        return (inCost + writeCost + readCost + outCost) * m
    }

    func cost(of events: [UsageEvent]) -> Double {
        events.reduce(0) { $0 + cost(of: $1) }
    }
}
