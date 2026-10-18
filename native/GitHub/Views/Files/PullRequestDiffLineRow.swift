import GitHub
import SwiftUI

/// One line of a pull request's diff: both line numbers (the gutter starts a comment), a change
/// marker, and the text. Its context menu holds everything a line offers, for touch and keyboard
/// users alike: comment, suggest, ask an agent, copy.
struct PullRequestDiffLineRow: View {
    let line: DiffHunk.Line
    let text: AttributedString?
    let numberTemplate: String
    let isSelected: Bool
    let model: PullRequestPageModel
    /// Where a comment on this line attaches; `nil` for lines GitHub can't anchor to.
    let anchor: ReviewAnchor?
    /// The current comment widened to this line, when that's possible.
    let extendAnchor: ReviewAnchor?
    let isShiftDown: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            gutter
            Text(marker)
                .foregroundStyle(tint ?? .dsTextTertiary)
                .frame(width: DS.Space.lg)
            Group {
                if let text, line.kind != .noNewline {
                    Text(text)
                } else {
                    Text(verbatim: line.text.isEmpty ? " " : line.text)
                        .foregroundStyle(line.kind == .noNewline ? Color.dsTextTertiary : Color.dsTextPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .padding(.trailing, DS.Space.md)
        .padding(.vertical, 1)
        .background(background)
        .overlay(alignment: .leading) {
            if let tint {
                Rectangle().fill(tint).frame(width: 2)
            }
        }
        .trackHover($isHovered)
        .contextMenu { menu }
    }

    /// Both line numbers; hovering shows a "+" to comment, as on GitHub.
    private var gutter: some View {
        Button {
            if isShiftDown, let extendAnchor {
                model.draft?.anchor = extendAnchor
                if let draft = model.draft { model.draft?.lines = model.lineText(for: draft.anchor) }
            } else if let anchor {
                model.beginComment(at: anchor)
            }
        } label: {
            HStack(spacing: 0) {
                number(line.oldNumber)
                number(line.newNumber)
            }
            .overlay(alignment: .trailing) {
                if (isHovered || DS.isTouchPlatform) && anchor != nil && model.page?.isOpen == true {
                    Image(systemName: "plus.square.fill")
                        .font(.system(size: DS.Size.navIcon))
                        .foregroundStyle(Color.dsAccent)
                        .opacity(isHovered ? 1 : 0.35)
                        .padding(.trailing, -DS.Space.xs)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(anchor == nil || model.page?.isOpen != true)
        .help(anchor.map { "Comment on \($0.lineDescription)" } ?? "")
        .accessibilityLabel(anchor.map { "Comment on \($0.lineDescription)" } ?? "Line")
    }

    private func number(_ value: Int?) -> some View {
        Text(verbatim: numberTemplate)
            .hidden()
            .overlay(alignment: .trailing) {
                if let value { Text(verbatim: String(value)) }
            }
            .foregroundStyle(.dsTextTertiary)
            .padding(.horizontal, DS.Space.sm)
    }

    @ViewBuilder private var menu: some View {
        if let anchor, model.page?.isOpen == true {
            Button("Comment on \(anchor.lineDescription.capitalizedFirst)", systemImage: "text.bubble") {
                model.beginComment(at: anchor)
            }
            if anchor.side == .right {
                Button("Suggest a Change", systemImage: "pencil.line") {
                    model.beginComment(at: anchor)
                    model.draft?.body = SuggestionBlock.fence(model.draft?.lines ?? line.text)
                }
            }
            if let extendAnchor {
                Button("Extend Comment to Here", systemImage: "arrow.down.to.line") {
                    model.draft?.anchor = extendAnchor
                    model.draft?.lines = model.lineText(for: extendAnchor)
                }
            }
        }
        if let anchor, model.canAskAgent {
            Divider()
            PullRequestAskAgentButtons(
                model: model, anchor: isSelected ? (model.draft?.anchor ?? anchor) : anchor, thread: nil)
        }
        Divider()
        Button("Copy Line", systemImage: "doc.on.doc") { model.gitHub?.copy(line.text) }
    }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "-"
        case .context, .noNewline: " "
        }
    }

    private var tint: Color? {
        switch line.kind {
        case .added: .dsSuccess
        case .removed: .dsDanger
        case .context, .noNewline: nil
        }
    }

    private var background: Color {
        if isSelected { return .dsAccentSubtle }
        switch line.kind {
        case .added: return Color.dsSuccess.opacity(0.12)
        case .removed: return Color.dsDanger.opacity(0.12)
        case .context, .noNewline: return .clear
        }
    }
}

extension String {
    /// "Line 4" from "line 4", for menu titles.
    fileprivate var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
