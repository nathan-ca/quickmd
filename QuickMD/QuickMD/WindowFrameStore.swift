import AppKit

/// Persists the most recent window frame — origin and size — so the next
/// standalone window, and the next launch, start exactly where the user
/// last left QuickMD instead of a fixed default position.
///
/// Only covers the main document window. The Open panel `DocumentGroup
/// (viewing:)` shows at launch when there's nothing to restore (see
/// session-restore.md) is SwiftUI-internal — there's no hook into its
/// position, so it always appears wherever AppKit/SwiftUI places it.
enum WindowFrameStore {
    private static let originXKey = "LastWindowOriginX"
    private static let originYKey = "LastWindowOriginY"
    private static let widthKey = "LastWindowWidth"
    private static let heightKey = "LastWindowHeight"

    private static var persistedFrame: NSRect? {
        let width = UserDefaults.standard.double(forKey: widthKey)
        let height = UserDefaults.standard.double(forKey: heightKey)
        guard width > 0, height > 0 else { return nil }
        let x = UserDefaults.standard.double(forKey: originXKey)
        let y = UserDefaults.standard.double(forKey: originYKey)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Apply the persisted frame to `window`, if one exists and still lands
    /// on a currently-connected screen — a saved position from a monitor
    /// that's since been unplugged, or a resolution change, is discarded
    /// rather than placing the window somewhere unreachable. Callers should
    /// only call this for standalone windows — a new tab joining an
    /// existing group should inherit that group's current frame instead of
    /// moving/resizing the whole group.
    static func applyPersistedFrame(to window: NSWindow) {
        guard let frame = persistedFrame, isFrameOnScreen(frame) else { return }
        window.setFrame(frame, display: true)
    }

    /// Start persisting `window`'s frame on every move/resize, until it
    /// closes. `didMoveNotification` covers dragging the window; the resize
    /// pair (`didEndLiveResizeNotification` for the end of a drag-resize,
    /// `didResizeNotification` guarded to skip the many events fired
    /// *during* a live drag) covers the rest, same as before.
    static func observeFrameChanges(of window: NSWindow) {
        var tokens: [NSObjectProtocol] = []

        tokens.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            persist(window.frame)
        })

        tokens.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification,
            object: window,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            persist(window.frame)
        })

        tokens.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow, !window.inLiveResize else { return }
            persist(window.frame)
        })

        // The close handler removes its own observer, which means reading a
        // token that's only assigned after this closure literal is created.
        // A plain `var` captured that way trips the Sendable-closure
        // "mutated after capture" check, since @Sendable closures can't
        // capture mutable state by reference. Boxing it in a reference type
        // sidesteps that: the box itself is a `let` (never reassigned,
        // capture-by-value-of-the-reference is fine), only its property
        // mutates. `@unchecked Sendable` because this box is only ever
        // touched from NotificationCenter callbacks on `.main`.
        let closeTokenBox = ObserverTokenBox()
        closeTokenBox.token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            tokens.forEach { NotificationCenter.default.removeObserver($0) }
            if let token = closeTokenBox.token {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    private static func isFrameOnScreen(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    private static func persist(_ frame: NSRect) {
        UserDefaults.standard.set(frame.origin.x, forKey: originXKey)
        UserDefaults.standard.set(frame.origin.y, forKey: originYKey)
        UserDefaults.standard.set(frame.size.width, forKey: widthKey)
        UserDefaults.standard.set(frame.size.height, forKey: heightKey)
    }
}

private final class ObserverTokenBox: @unchecked Sendable {
    var token: NSObjectProtocol?
}
