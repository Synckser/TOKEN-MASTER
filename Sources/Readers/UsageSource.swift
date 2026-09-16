import Foundation

/// A reader that incrementally yields new usage events from an on-disk log tree.
/// Isolate all path/format logic behind this so a future Windows port swaps only
/// the concrete reader.
protocol UsageSource: AnyObject {
    var source: UsageEvent.Source { get }
    /// Returns events appended since the previous call (all events on first call).
    /// Must tolerate missing/locked/partial files: skip and keep going.
    func scan() -> [UsageEvent]
}

/// Shared helpers for line-oriented JSONL readers with per-file byte offsets.
class IncrementalJSONLReader {
    /// Byte offset already consumed, per file path.
    var offsets: [String: UInt64] = [:]
    let fm = FileManager.default

    /// Enumerate files under `root` whose name matches `predicate`.
    func files(under root: URL, matching predicate: (String) -> Bool) -> [URL] {
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in en where predicate(url.lastPathComponent) {
            result.append(url)
        }
        return result
    }

    /// Read new lines appended to `url` since the last scan. Handles truncation
    /// (file shorter than stored offset) by resetting to 0.
    func newLines(in url: URL) -> [Data] {
        let path = url.path
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let end = (try? handle.seekToEnd()) ?? 0
        var start = offsets[path] ?? 0
        if start > end { start = 0 } // file rotated/truncated

        guard start < end else { return [] }
        do { try handle.seek(toOffset: start) } catch { return [] }

        let data = (try? handle.readToEnd()) ?? Data()
        offsets[path] = start + UInt64(data.count)

        return data.split(separator: 0x0A).map { Data($0) }
    }

    /// ISO8601 with and without fractional seconds.
    static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    func parseDate(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return Self.isoFrac.date(from: s) ?? Self.iso.date(from: s)
    }

    /// Depth-first search for the first nested dictionary stored under `key`.
    func findDict(_ any: Any, key: String) -> [String: Any]? {
        if let d = any as? [String: Any] {
            if let v = d[key] as? [String: Any] { return v }
            for (_, val) in d {
                if let f = findDict(val, key: key) { return f }
            }
        } else if let arr = any as? [Any] {
            for val in arr {
                if let f = findDict(val, key: key) { return f }
            }
        }
        return nil
    }

    func int(_ d: [String: Any], _ key: String) -> Int {
        if let i = d[key] as? Int { return i }
        if let n = d[key] as? NSNumber { return n.intValue }
        return 0
    }
}
