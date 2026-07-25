import Foundation
import CoreServices

/// Watches a set of directory trees recursively for filesystem changes,
/// using FSEvents — unlike `FileWatcher`'s kqueue-based approach (one
/// descriptor per file, no recursion), a single FSEvents stream covers an
/// entire subtree regardless of depth, which is what makes it practical for
/// the folder tree sidebar's live updates.
///
/// Doesn't report *what* changed — any event just means "something changed
/// somewhere in these trees," coalesced with a debounce the same way
/// `FileWatcher` debounces rapid saves. The caller re-scans; directory
/// listings are cheap enough that this is simpler than trying to diff which
/// specific node changed.
///
/// Main-thread by convention, deliberately NOT @MainActor — matches
/// `FileWatcher`'s reasoning: SwiftUI view callbacks that create/drive this
/// are nonisolated on older SDKs, and an isolated call there is a hard
/// compile error on the CI toolchain.
final class DirectoryTreeWatcher {

    /// Fired (debounced) when something changed anywhere under the watched
    /// paths.
    var onChange: (() -> Void)?

    private var stream: FSEventStreamRef?
    private var debounce: DispatchWorkItem?

    private static let debounceInterval: TimeInterval = 0.4

    /// Start watching `paths` (replaces any previous watch). FSEvents
    /// streams aren't incrementally updatable — adding or removing a root
    /// means tearing down and recreating the stream with the full new path
    /// list, which is fine since that only happens on a user-driven
    /// add/remove, not a hot path.
    func start(watching urls: [URL]) {
        stop()
        guard !urls.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
            guard let clientCallBackInfo else { return }
            let watcher = Unmanaged<DirectoryTreeWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            watcher.scheduleChange()
        }

        let paths = urls.map(\.path) as CFArray
        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
        ) else {
            return
        }

        stream = newStream
        FSEventStreamSetDispatchQueue(newStream, .main)
        FSEventStreamStart(newStream)
    }

    func stop() {
        debounce?.cancel()
        debounce = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.debounce = nil
            self?.onChange?()
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    deinit {
        stop()
    }
}
