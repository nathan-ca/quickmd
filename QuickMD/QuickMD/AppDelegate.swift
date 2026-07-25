import AppKit

/// Reopens documents that were open when the app last quit, before
/// `NSDocumentController` falls back to its default "show an Open panel"
/// behavior. `DocumentGroup(viewing:)` apps (QuickMD is a viewer, not an
/// editor) don't get automatic window/state restoration from the system
/// the way editable document apps do — this fills that gap. If nothing was
/// persisted, this does nothing and today's existing Open-panel-on-launch
/// behavior takes over unchanged.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set the moment AppKit begins quitting, before it starts closing
    /// windows — so in-flight tab teardown (which fires the same SwiftUI
    /// `onDisappear` as a user closing one tab) can tell the difference and
    /// skip unregistering from `OpenDocumentsStore`. Without this, every
    /// open tab "closes" as part of quitting and wipes the very state we're
    /// trying to persist for next launch (see session-restore.md). Always
    /// set/read on the main thread — AppKit delegate callbacks and SwiftUI
    /// view callbacks both run there.
    nonisolated(unsafe) private(set) static var isTerminating = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.isTerminating = true
        return .terminateNow
    }

    /// `DocumentGroup(viewing:)` shows its own Open panel the moment the
    /// scene first evaluates with zero open documents — a SwiftUI-internal
    /// decision, not routed through `NSApplicationDelegate`'s classic
    /// untitled-file hooks (confirmed: `applicationShouldOpenUntitledFile`
    /// is never called for this document type). Since our reopen below is
    /// async, that panel can flash briefly before auto-dismissing once the
    /// restored windows land. No supported API prevents it — see
    /// session-restore.md for what was tried and why it was left as-is.
    func applicationWillFinishLaunching(_ notification: Notification) {
        let urls = OpenDocumentsStore.loadPersistedURLs()
        guard !urls.isEmpty else { return }

        for url in urls {
            NSDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true,
                completionHandler: { _, _, error in
                    if let error {
                        assertionFailure("Session restore failed to reopen \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            )
        }
    }
}
