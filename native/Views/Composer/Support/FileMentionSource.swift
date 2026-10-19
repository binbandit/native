import ACP
import Foundation
import Observation

/// The files and folders the `@` list offers for one project: listed once when the first `@` is
/// typed (and again when the session's folder changes), ranked per keystroke. Folders end in "/".
@Observable
final class FileMentionSource {
    private let index: (any ProjectFileIndex)?
    private(set) var entries: [String] = []
    private(set) var changed: Set<String> = []
    /// Files and folders mentioned in this composer, most recent first.
    private(set) var recent: [String] = []
    private var isLoaded = false

    init(root: URL) {
        index = ComposerPlatform.fileIndex(for: root)
    }

    func loadIfNeeded() async {
        guard !isLoaded, let index else { return }
        isLoaded = true
        async let files = index.files()
        async let changed = index.changedFiles()
        entries = FileMention.entries(forFiles: (try? await files) ?? [])
        self.changed = await changed
    }

    func matches(for query: String) -> [String] {
        FileMentionMatcher(changed: changed, recent: recent).matches(for: query, in: entries, limit: 50)
    }

    func noteMentioned(_ path: String) {
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
    }
}
