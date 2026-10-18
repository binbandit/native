import Foundation

/// Search across every agent run (docs/search.md): the index, the panel and its command. Built in
/// and on, since it adds nothing to the window until the user asks for it (⇧⌘F).
struct TranscriptSearchPlugin: NativePlugin {
    let manifest = PluginManifest(
        id: "search",
        name: "Search",
        description:
            "Find any task by what was said in it: prompts, replies, commands and file paths, across every agent and project. The index stays on this Mac."
    )

    let center = TranscriptSearchCenter()

    func handle(_ event: SessionEvent) async {
        center.handle(event)
    }
}

extension BuiltInPlugins {
    /// One instance for the app: the composition root connects its center, and the panel, menu and
    /// sidebar read the same one.
    static let search = TranscriptSearchPlugin()
}

/// The one way into search for other features (the command palette offers "Search transcripts for
/// '…'" through it).
enum TranscriptSearch {
    /// Shows the search panel, with `query` in its field when given.
    static func open(query: String? = nil) {
        BuiltInPlugins.search.center.present(query: query)
    }
}
