import SwiftUI

/// Tracks which documents are currently open in a tab/window, persisted so
/// they can be reopened on next launch. Distinct from `RecentDocumentsStore`,
/// which tracks history of ever-opened files and doesn't distinguish open
/// from closed.
@MainActor
final class OpenDocumentsStore: ObservableObject {
    static let shared = OpenDocumentsStore()

    private nonisolated static let openURLsKey = "OpenDocumentURLs"

    @Published private(set) var openURLs: Set<URL> = []

    private init() {
        openURLs = Set(Self.loadPersistedURLs())
    }

    /// Reads the persisted set directly from `UserDefaults` without going
    /// through `.shared` — used once at launch, before any document has
    /// registered itself as open, to decide what to reopen. Deliberately
    /// `nonisolated`: it's a stateless read, and callers (like the app
    /// delegate's launch hook) shouldn't have to prove they're on the main
    /// actor just to ask "what was open last time."
    nonisolated static func loadPersistedURLs() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: openURLsKey) ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }

    func register(_ url: URL) {
        openURLs.insert(url.standardizedFileURL)
        persist()
    }

    func unregister(_ url: URL) {
        openURLs.remove(url.standardizedFileURL)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(openURLs.map(\.path), forKey: Self.openURLsKey)
    }
}
