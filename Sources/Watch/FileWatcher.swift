import Foundation

/// Watches directory trees with FSEvents and fires a debounced callback.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let onChange: () -> Void
    private let debounce: TimeInterval
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "tokenmaster.fswatch")

    init(paths: [String], debounce: TimeInterval = 0.4, onChange: @escaping () -> Void) {
        self.paths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        self.debounce = debounce
        self.onChange = onChange
    }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }

        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.fire()
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &ctx,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, flags
        ) else { return }

        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func fire() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    deinit { stop() }
}
