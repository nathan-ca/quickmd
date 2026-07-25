import SwiftUI
import AppKit

// MARK: - Window Configurator

/// Bridges into AppKit to configure the host NSWindow once it's available.
/// Used to opt every document window into native macOS tabbing — we set the
/// shared `tabbingIdentifier` and, if another QuickMD doc window is already
/// visible, programmatically merge the new window as a tab.
///
/// We can't rely on AppKit's auto-tabbing (controlled by the system-wide
/// "Prefer tabs" pref) because we want consistent tab UX regardless of user
/// settings. `addTabbedWindow` is the explicit override.
struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TabAwareView()
        view.onWindowAttached = { window in
            configure(window)
            let merged = mergeIntoExistingTabIfPossible(window: window)
            if !merged {
                // Standalone window (first window of the session, or every
                // other window has since closed) — restore the frame the
                // user last left a QuickMD window at. A tab merged into an
                // existing group is deliberately left alone above; it
                // inherits the group's current frame, matching native tab
                // behavior instead of moving/resizing the whole group to a
                // historical position.
                WindowFrameStore.applyPersistedFrame(to: window)
            }
            WindowFrameStore.observeFrameChanges(of: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @discardableResult
    private func mergeIntoExistingTabIfPossible(window newWindow: NSWindow) -> Bool {
        // Find another visible QuickMD document window already on screen and
        // merge the new window into its tab group.
        guard let identifier = newWindow.tabbingIdentifier as String?,
              !identifier.isEmpty else { return false }

        let candidates = NSApp.windows.filter { other in
            other !== newWindow
                && other.isVisible
                && other.tabbingIdentifier == newWindow.tabbingIdentifier
                && other.tabGroup !== newWindow.tabGroup  // not already grouped
        }
        guard let host = candidates.first else { return false }
        host.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
        return true
    }
}

/// NSView subclass that fires `onWindowAttached` exactly once, when the host
/// NSWindow becomes available via `viewDidMoveToWindow`. More reliable than
/// `DispatchQueue.main.async` polling.
private final class TabAwareView: NSView {
    var onWindowAttached: ((NSWindow) -> Void)?
    private var fired = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !fired, let window = self.window else { return }
        fired = true
        onWindowAttached?(window)
    }
}
