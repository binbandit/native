import ACP
import SwiftUI

/// Changes owns the anchors; the task owns their drafts, so switching files never loses words.
struct DiffCommentsView: View {
    let session: SessionModel
    let path: String
    let oldText: String?
    let newText: String
    let layout: DiffLayout?
    var initialSelection: PromptQuote? = nil
    var initiallyFocusesComment = false

    @Environment(\.diffCommentsScope) private var scope
    @Environment(\.undoManager) private var undoManager
    @State private var anchor: Int?
    @State private var current = 0
    @State private var shiftDown = false
    @State private var side = PromptQuote.Side.new
    @State private var sourceID = UUID()
    @State private var rowFrames: [Int: CGRect] = [:]
    @FocusState private var commentFocused: Bool
    @FocusState private var lineFocused: Bool

    private var rows: [DiffRow] { layout?.rows ?? DiffRow.rows(oldText: oldText, newText: newText).rows }
    private var fingerprint: String { PromptDiffComment.fingerprint(old: oldText, new: newText) }
    private var range: ClosedRange<Int> { min(anchor ?? current, current)...max(anchor ?? current, current) }
    private var comments: [PromptQuote] { session.diffComments.filter { $0.source == path } }
    private var editors: [PromptQuote] { session.diffCommentEditors.filter { $0.source == path } }

    var body: some View {
        VStack(spacing: 0) {
            header
            SeparatorLine()
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows.indices, id: \.self) { index in
                            row(index).id(index)
                            annotations(after: index)
                        }
                        ForEach(comments.filter { !isCurrent($0) }) { quote in
                            DiffCommentsAnnotation(session: session, quote: quote, stale: true)
                        }
                        ForEach(
                            editors.filter {
                                !isCurrent($0) && !session.diffCommentEditsInComposer
                                    && $0.comment?.id == session.activeDiffComment
                            }
                        ) {
                            quote in
                            DiffCommentsEditor(session: session, quote: quote)
                        }
                    }
                    .padding(.top, DS.Space.md)
                    .coordinateSpace(name: sourceID)
                    .onPreferenceChange(DiffCommentsRowFrames.self) { frames in
                        if rowFrames != frames { rowFrames = frames }
                    }
                    .focusable()
                    .focused($lineFocused)
                    .dsFocusShape(Rectangle())
                    .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], action: moveLine)
                }
                .onChange(of: session.diffCommentRequestedSource) { _, quote in
                    guard let quote, isCurrent(quote), let last = lastIndex(quote) else { return }
                    side = quote.side
                    current = last
                    anchor = rows.firstIndex { row in
                        let number = quote.side == .old ? row.oldNumber : row.number
                        return number == quote.lines.first?.number
                    }
                    lineFocused = true
                    reader.scrollTo(last, anchor: .center)
                }
                .onChange(of: session.activeDiffComment) { _, id in
                    if let quote = editors.first(where: { $0.comment?.id == id }), let index = lastIndex(quote) {
                        reader.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
        .diffCommentsTrackingShift($shiftDown)
        .onAppear {
            selectFirstLine()
            if let initialSelection, let end = lastIndex(initialSelection) {
                side = initialSelection.side
                current = end
                anchor = rows.firstIndex { $0.number == initialSelection.lines.first?.number && $0.kind != .removed }
                publishSelection()
            }
            commentFocused = initiallyFocusesComment
        }
        .onChange(of: path) {
            anchor = nil; current = 0; selectFirstLine()
        }
        .onChange(of: fingerprint) {
            anchor = nil; current = 0; selectFirstLine()
        }
        .onChange(of: session.diffCommentFocusRequest) { _, _ in
            if session.activeDiffComment == nil { lineFocused = true }
        }
        .onDisappear {
            session.clearQuoteSelection(source: sourceID)
            if session.diffCommentSelection?.source == path,
                session.diffCommentSelection?.comment?.fingerprint == fingerprint
            {
                session.diffCommentSelection = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.lg) {
            Text(anchor == nil ? (path as NSString).lastPathComponent : sourceLabel)
                .font(DS.ComposerQuote.headerFont)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DS.Space.xs)
            Button(session.reanchoringDiffComment == nil ? "Comment…" : "Use Selected Lines") {
                if let id = session.reanchoringDiffComment {
                    session.reanchorDiffComment(id, undoManager: undoManager)
                } else {
                    session.beginDiffComment(selection)
                    lineFocused = false
                }
            }
            .buttonStyle(.ds(.secondary))
            .disabled(
                selection == nil || !session.diffCommentRetentionAllowed
                    || (session.reanchoringDiffComment != nil && session.diffCommentSelection == nil)
            )
            .focused($commentFocused)
            .accessibilityLabel("Comment on Selected Lines")
            .accessibilityHint("Write a comment to add to this task’s draft.")
            Button("Quote") { if var quote = selection { quote.comment = nil; session.quote([quote]) } }
                .buttonStyle(.ds(.ghost))
                .disabled(selection == nil || !session.diffCommentRetentionAllowed)
        }
        .padding(.horizontal, DS.Space.xl)
        .frame(minHeight: DS.DiffComments.headerHeight)
    }

    private var sourceLabel: String {
        guard let selection, let first = selection.lines.first?.number, let last = selection.lines.last?.number else {
            return (path as NSString).lastPathComponent
        }
        return "\(side == .old ? "Before" : "After") · \(first == last ? "line \(first)" : "lines \(first)-\(last)")"
    }

    private var selection: PromptQuote? {
        guard rows.indices.contains(current) else { return nil }
        let sourceRows = rows.map { row in
            PromptDiffCommentSelection.Row(
                before: row.oldNumber.map { .init(number: $0, text: row.text) },
                after: row.kind == .removed ? nil : row.number.map { .init(number: $0, text: row.text) })
        }
        guard var quote = PromptDiffCommentSelection.quote(source: path, rows: sourceRows, range: range, side: side)
        else {
            return nil
        }
        quote.comment = PromptDiffComment(task: session.clientID, scope: scope, fingerprint: fingerprint, body: "")
        return quote
    }

    private func selectFirstLine() {
        guard let first = rows.firstIndex(where: { $0.number != nil }) else { return }
        current = first
        side = rows[first].kind == .removed ? .old : .new
        publishSelection()
    }

    private func select(_ index: Int, side: PromptQuote.Side, extend: Bool) {
        guard rows.indices.contains(index), rows[index].number != nil else { return }
        guard side == .old ? rows[index].oldNumber != nil : rows[index].kind != .removed else { return }
        let start = extend && self.side == side ? (anchor ?? current) : index
        // A gap is a hunk boundary. Opposite-side changes can be skipped, but never a hidden range.
        guard !rows[min(start, index)...max(start, index)].contains(where: { $0.kind == .gap }) else { return }
        self.side = side
        anchor = start
        current = index
        lineFocused = true
        publishSelection()
    }

    private func publishSelection() {
        guard var selected = selection else { return }
        session.selectDiffCommentLines(selected)
        selected.comment = nil
        session.selectQuote([selected], source: sourceID)
    }

    private func row(_ index: Int) -> some View {
        let row = rows[index]
        return HStack(alignment: .top, spacing: 0) {
            gutter(index, number: row.oldNumber, side: .old)
            gutter(index, number: row.kind == .removed ? nil : row.number, side: .new)
            Text(row.kind == .added ? "+" : row.kind == .removed ? "−" : " ")
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.DiffComments.marker)
            Text(verbatim: row.text.isEmpty ? " " : row.text)
                .font(DS.DiffComments.codeFont)
                .foregroundStyle(row.kind == .gap ? .dsTextTertiary : .dsTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, DS.Space.xl)
                .textSelection(.enabled)
        }
        .frame(minHeight: DS.isTouchPlatform ? DS.Size.minimumHitTarget : DS.DiffComments.lineHeight)
        .background(
            row.kind == .added
                ? Color.dsSuccess.opacity(0.12)
                : row.kind == .removed ? Color.dsDanger.opacity(0.12) : .clear
        )
        .overlay {
            if anchor != nil, range.contains(index), row.kind != .gap,
                side == .old ? row.oldNumber != nil : row.kind != .removed
            {
                Rectangle().fill(.dsSelected).allowsHitTesting(false)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DiffCommentsRowFrames.self,
                    value: [index: proxy.frame(in: .named(sourceID)).integral])
            }
        }
        .composerQuoteSource(
            ComposerQuoteSource(
                name: path, text: row.number == nil ? nil : row.text,
                firstLine: row.number ?? 1, side: row.kind == .removed ? .old : .new)
        )
        .transformEnvironment(\.composerQuoteContext) { context in
            if row.number == nil { context = nil }
        }
        .overlay(alignment: .leading) {
            if row.kind == .added || row.kind == .removed {
                Rectangle().fill(row.kind == .added ? Color.dsSuccess : Color.dsDanger)
                    .frame(width: DS.Space.xxs)
            }
        }
    }

    private func moveLine(_ press: KeyPress) -> KeyPress.Result {
        let newSide: PromptQuote.Side = press.key == .leftArrow ? .old : press.key == .rightArrow ? .new : side
        let step = press.key == .upArrow ? -1 : press.key == .downArrow ? 1 : 0
        let sourceRows = rows.map { row in
            PromptDiffCommentSelection.Row(
                before: row.oldNumber.map { .init(number: $0, text: row.text) },
                after: row.kind == .removed ? nil : row.number.map { .init(number: $0, text: row.text) })
        }
        if let next = PromptDiffCommentSelection.nextIndex(
            in: sourceRows, from: current, step: step,
            side: newSide, extending: press.modifiers.contains(.shift))
        {
            select(next, side: newSide, extend: press.modifiers.contains(.shift))
        }
        return .handled
    }

    private func gutter(_ index: Int, number: Int?, side: PromptQuote.Side) -> some View {
        Group {
            if let number {
                Button {
                    select(index, side: side, extend: shiftDown)
                } label: {
                    Text(verbatim: String(number)).frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .dsHitTarget(DS.DiffComments.lineHeight)
                .accessibilityLabel("\(side == .old ? "Before" : "After"), line \(number), \(rows[index].text)")
                .accessibilityValue(
                    anchor != nil && range.contains(index) && side == self.side ? "\(sourceLabel) selected" : ""
                )
                .contextMenu {
                    Button("Extend Selection to Here") { select(index, side: side, extend: true) }
                    Button("Comment…") {
                        select(index, side: side, extend: false); session.beginDiffComment(selection)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(sourceID))
                        .onChanged { value in
                            if let target = rowFrames.first(where: { $0.value.contains(value.location) })?.key {
                                select(target, side: side, extend: shiftDown || value.translation != .zero)
                            }
                        })
            } else {
                Text(" ")
            }
        }
        .font(DS.ComposerQuote.numberFont)
        .foregroundStyle(.dsTextTertiary)
        .padding(.trailing, DS.Space.md)
        .frame(width: DS.DiffComments.gutter)
    }

    private func isCurrent(_ quote: PromptQuote) -> Bool {
        quote.comment?.matches(scope: scope, fingerprint: fingerprint) == true && lastIndex(quote) != nil
    }

    private func lastIndex(_ quote: PromptQuote) -> Int? {
        guard let line = quote.lines.last else { return nil }
        return rows.lastIndex { row in
            let number = quote.side == .old ? row.oldNumber : (row.kind == .removed ? nil : row.number)
            return number == line.number && row.text == line.text
        }
    }

    @ViewBuilder private func annotations(after index: Int) -> some View {
        ForEach(comments.filter { isCurrent($0) && lastIndex($0) == index }) { quote in
            if session.activeDiffComment != quote.comment?.id || session.diffCommentEditsInComposer {
                DiffCommentsAnnotation(session: session, quote: quote, stale: false)
            }
        }
        ForEach(
            editors.filter {
                isCurrent($0) && lastIndex($0) == index && !session.diffCommentEditsInComposer
                    && $0.comment?.id == session.activeDiffComment
            }
        ) { quote in
            DiffCommentsEditor(session: session, quote: quote)
        }
    }
}

extension PromptQuote: @retroactive Identifiable {
    public nonisolated var id: String { comment?.id.uuidString ?? prompt }
}

private nonisolated struct DiffCommentsRowFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

#if DEBUG
#Preview("DiffCommentsView - States") {
    DSPreviewPair {
        DiffCommentsPreviewHost("C1") { session in
            DiffCommentsView(
                session: session, path: DiffCommentsPreviewFixtures.path, oldText: DiffCommentsPreviewFixtures.old,
                newText: DiffCommentsPreviewFixtures.new, layout: nil
            ).frame(width: DS.DiffComments.referencePaneWidth, height: 560)
        }
    }
}
#endif
