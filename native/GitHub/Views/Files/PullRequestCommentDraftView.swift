import GitHub
import SwiftUI

/// The new line comment, under its lines: Markdown with Write / Preview, "Suggest a Change", and
/// GitHub's two ways to send it: into a review, or as a single comment right away.
struct PullRequestCommentDraftView: View {
    let model: PullRequestPageModel

    var body: some View {
        if let draft = model.draft {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.sm) {
                    Text("Comment on \(draft.anchor.lineDescription)")
                        .font(.dsCaptionMedium)
                        .foregroundStyle(.dsTextSecondary)
                    Spacer(minLength: DS.Space.md)
                    if draft.anchor.side == .right {
                        Button("Suggest a Change", systemImage: "pencil.line") {
                            model.draft?.body += (draft.body.isEmpty ? "" : "\n") + SuggestionBlock.fence(draft.lines)
                        }
                        .buttonStyle(.ds(.ghost))
                        .help("Proposes replacement lines the author can apply on GitHub")
                    }
                    if model.canAskAgent {
                        Menu {
                            PullRequestAskAgentButtons(model: model, anchor: draft.anchor, thread: nil, request: draft.body)
                        } label: {
                            Label("Ask an Agent", systemImage: "sparkles")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.ds(.ghost))
                        .fixedSize()
                        .help("Sends these lines, with what you wrote as the request")
                    }
                }
                GitHubCommentComposer(
                    text: Binding(get: { model.draft?.body ?? "" }, set: { model.draft?.body = $0 }),
                    placeholder: "Leave a comment. Markdown works.", isBusy: model.busy.contains("draft"),
                    focusesOnAppear: true
                ) {
                    Button("Cancel") { model.draft = nil }
                        .buttonStyle(.ds(.ghost))
                        .keyboardShortcut(.cancelAction)
                    if model.page?.pendingReview == nil {
                        Button("Add Single Comment") { Task { await model.sendDraft(asReview: false) } }
                            .buttonStyle(.ds(.secondary))
                            .disabled(isEmpty)
                    }
                    Button(model.page?.pendingReview == nil ? "Start a Review" : "Add Review Comment") {
                        Task { await model.sendDraft(asReview: true) }
                    }
                    .buttonStyle(.ds(.primary))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isEmpty)
                }
            }
            .padding(DS.Space.md)
            .background(.dsSurface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(.dsSeparator, lineWidth: 1)
            }
            .codeTextStyle(.block)
        }
    }

    private var isEmpty: Bool {
        (model.draft?.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
