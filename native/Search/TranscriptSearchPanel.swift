import Search
import SwiftUI

/// Search across every task (⇧⌘F): a field, filters, and results grouped by task. ↑/↓ move through
/// tasks and hits, Return opens the selected one at the exact message, Escape clears the field and
/// then closes the panel.
struct TranscriptSearchPanel: View {
    @Bindable var center: TranscriptSearchCenter

    @Environment(AppModel.self) private var model
    @FocusState private var isFieldFocused: Bool
    @State private var selection: TranscriptSearchRow.ID?

    var body: some View {
        let rows = TranscriptSearchRow.rows(of: center.results.groups)
        VStack(spacing: 0) {
            field(rows: rows)
            TranscriptSearchFilterBar(
                filters: $center.filters, agents: model.plugins.agents, projects: model.projects.all
            )
            .padding(.horizontal, DS.Space.lg)
            .padding(.bottom, DS.Space.md)
            SeparatorLine()
            if let status = indexingStatus {
                status
                SeparatorLine()
            }
            content(rows: rows)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            SeparatorLine()
            footer
        }
        // A fixed size on the Mac, so the sheet doesn't grow with its results; full screen on touch.
        .frame(
            width: DS.isTouchPlatform ? nil : TranscriptSearchMetrics.panelWidth,
            height: DS.isTouchPlatform ? nil : TranscriptSearchMetrics.panelHeight
        )
        .background(.dsBackground)
        .onAppear { isFieldFocused = true }
        .onChange(of: center.results) { _, results in
            // The best match, so Return goes straight to it.
            let rows = TranscriptSearchRow.rows(of: results.groups)
            selection = (rows.first { $0.hit != nil } ?? rows.first)?.id
        }
    }

    // MARK: - Field

    private func field(rows: [TranscriptSearchRow]) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "magnifyingglass")
                .font(.dsCallout)
                .foregroundStyle(.dsTextTertiary)
                .accessibilityHidden(true)
            TextField("Search every task", text: $center.query)
                .textFieldStyle(.plain)
                .font(.dsHeadline)
                .focused($isFieldFocused)
                .accessibilityLabel("Search every task")
                .onKeyPress(.downArrow) { move(1, in: rows) }
                .onKeyPress(.upArrow) { move(-1, in: rows) }
                .onKeyPress(.return) { openSelection(in: rows) }
                .onKeyPress(.escape) {
                    if center.query.isEmpty {
                        center.isPresented = false
                    } else {
                        center.query = ""
                    }
                    return .handled
                }
            if !center.query.isEmpty {
                Button {
                    center.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.dsTextTertiary)
                .accessibilityLabel("Clear search")
                .dsHitTarget(DS.Size.statusGlyph)
            }
            Button("Close") { center.isPresented = false }
                .buttonStyle(.ds(.ghost))
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    private func move(_ offset: Int, in rows: [TranscriptSearchRow]) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.id == selection } ?? (offset > 0 ? -1 : rows.count)
        selection = rows[min(max(current + offset, 0), rows.count - 1)].id
        return .handled
    }

    private func openSelection(in rows: [TranscriptSearchRow]) -> KeyPress.Result {
        guard let row = rows.first(where: { $0.id == selection }) ?? rows.first else { return .ignored }
        center.open(row.group, hit: row.hit)
        return .handled
    }

    // MARK: - Content

    @ViewBuilder private func content(rows: [TranscriptSearchRow]) -> some View {
        if !center.isEnabled {
            EmptyStateView(
                "Search is off",
                systemImage: "magnifyingglass",
                message: "Turn it on to index your tasks on this Mac and find any of them by what was said in it."
            ) {
                Button("Turn On Search") { center.turnOn() }
            }
        } else if let failure = center.failure {
            ErrorState(
                "Search isn't available",
                recovery: failure,
                suggestion: "Your tasks are untouched; only the index is affected.",
                primary: .init("Try Again") { center.reopen() },
                layout: .pane)
        } else if !center.results.groups.isEmpty {
            VStack(spacing: 0) {
                if isBlank {
                    recentHeader
                }
                TranscriptSearchResultsList(groups: center.results.groups, selection: $selection) { row in
                    center.open(row.group, hit: row.hit)
                }
            }
        } else if let searchFailure = center.searchFailure {
            ErrorState(
                "The search didn't finish", recovery: searchFailure, primary: .init("Try Again") { center.retry() })
        } else if isWaiting {
            Color.clear
        } else if isBlank {
            blankState
        } else {
            noResults
        }
    }

    /// Over the latest tasks, before anything is typed: what they are and how to narrow a search.
    private var recentHeader: some View {
        HStack(spacing: DS.Space.md) {
            Text("Recent tasks")
                .font(.dsCaptionMedium)
                .foregroundStyle(.dsTextSecondary)
            Spacer(minLength: DS.Space.md)
            Text("Narrow with agent:codex, project:native, role:user, has:diff")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.md)
    }

    /// Nothing typed and no filters.
    private var isBlank: Bool {
        center.query.trimmingCharacters(in: .whitespaces).isEmpty && center.filters.isEmpty
    }

    /// The current query hasn't been answered yet; the previous results stay until it is.
    private var isWaiting: Bool {
        center.answeredQuery?.text != center.query || center.answeredQuery?.filters != center.filters
    }

    @ViewBuilder private var blankState: some View {
        if (center.statistics?.sessions ?? 0) == 0, center.indexing != .idle {
            EmptyStateView(
                "Indexing your tasks",
                systemImage: "magnifyingglass",
                message:
                    "Native is reading your agents' past tasks so you can search them. Results appear as they're indexed."
            ) {}
        } else {
            EmptyStateView(
                "Search every task",
                systemImage: "magnifyingglass",
                message:
                    "Find any task by what was said in it: prompts, replies, commands and file paths, across every agent and project. Narrow it with agent:codex, project:native, role:user, has:diff or after:2026-10-01."
            ) {}
        }
    }

    private var noResults: some View {
        EmptyStateView(
            center.query.isEmpty ? "No tasks match these filters" : "No matches for “\(center.query)”",
            systemImage: "magnifyingglass",
            message: noResultsAdvice
        ) {
            if !center.filters.isEmpty {
                Button("Clear Filters") { center.filters = SearchFilters() }
            }
            if !center.filters.includeArchived {
                Button("Include Archived") { center.filters.includeArchived = true }
                    .buttonStyle(.ds(center.filters.isEmpty ? .primary : .secondary))
            }
        }
    }

    private var noResultsAdvice: String {
        var advice = ["Try fewer words, or part of a word: \"rollb\" finds \"rollback\"."]
        if case .indexing(let done, let total) = center.indexing {
            advice.insert("Still indexing: \(total - done) tasks to go, so more may turn up.", at: 0)
        }
        return advice.joined(separator: " ")
    }

    // MARK: - Status and footer

    private var indexingStatus: (some View)? {
        let text: String? =
            switch center.indexing {
            case .idle: nil
            case .indexing(let done, let total): "Indexing past tasks · \(done) of \(total)"
            case .paused(let done, let total):
                "Indexing paused on battery · \(done) of \(total) · continues when your Mac is plugged in"
            }
        return text.map { text in
            HStack(spacing: DS.Space.md) {
                if case .indexing = center.indexing {
                    DotGridLoader(pattern: .waiting)
                        .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                } else {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(.dsTextTertiary)
                }
                Text(text)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm)
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.lg) {
            hint("↑↓", "Move")
            hint("↩", "Open")
            hint("esc", center.query.isEmpty ? "Close" : "Clear")
            Spacer(minLength: DS.Space.md)
            Text(summary)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Size.controlMD)
    }

    private func hint(_ keys: String, _ action: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Kbd(keys)
            Text(action)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
        }
    }

    private var summary: String {
        let groups = center.results.groups
        guard !groups.isEmpty else {
            return center.statistics.map { "\($0.sessions) tasks indexed" } ?? ""
        }
        let tasks = groups.count == 1 ? "1 task" : "\(groups.count)\(center.results.isTruncated ? "+" : "") tasks"
        let milliseconds = Int((center.results.duration * 1000).rounded())
        return "\(tasks) · \(milliseconds) ms"
    }
}
