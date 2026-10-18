import NativeCommands

extension CommandID {
    static let searchShow: Self = "search.show"
}

extension NativeCommand {
    /// Go ▸ Search Tasks… (⇧⌘F). The palette offers it for whatever's typed, as "Search Tasks for
    /// “…”", rather than searching transcripts itself.
    static let searchShow = NativeCommand(
        .searchShow, title: "Search Tasks…", category: .navigation, systemImage: "magnifyingglass",
        keywords: ["find", "transcripts", "history"]
    ) { _ in
        TranscriptSearch.open()
    }
    .takesQuery { query, _ in
        TranscriptSearch.open(query: query)
    }
}
