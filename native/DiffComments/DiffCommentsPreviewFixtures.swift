#if DEBUG
import ACP
import SwiftUI
import NativePolicy

@MainActor
enum DiffCommentsPreviewFixtures {
    static let path = "native/DesignSystem/Diff/DiffRow.swift"
    static let prefix = (1...42).map { "// Context \($0)" }.joined(separator: "\n") + "\n"
    static let old =
        prefix + """
            var body: some View {
                HStack(alignment: .top, spacing: 0) {
                    lineNumbers
                    Text(line.text)
                        .font(.dsMono)
                        .lineLimit(1)
                }
            }
            """
    static let new =
        prefix + """
            var body: some View {
                HStack(alignment: .top, spacing: 0) {
                    lineNumbers
                    Text(line.text)
                        .font(.dsMono)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineBreakStrategy(.standard)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            """

    static func quotes(task: UUID) -> [PromptQuote] {
        [
            PromptQuote(
                source: path, side: .new,
                lines: [
                    .init(number: 49, text: "            .lineBreakStrategy(.standard)"),
                    .init(number: 50, text: "            .fixedSize(horizontal: false, vertical: true)"),
                ],
                comment: PromptDiffComment(
                    task: task, scope: "Uncommitted",
                    fingerprint: PromptDiffComment.fingerprint(old: old, new: new),
                    body: "Keep long identifiers inside the code column too.")),
            PromptQuote(
                source: "Tests/DiffLayoutTests.swift", side: .new,
                lines: [.init(number: 81, text: "#expect(row.gutterWidth == originalGutterWidth)")],
                comment: PromptDiffComment(
                    task: task, scope: "Uncommitted", fingerprint: "tests",
                    body: "Add a test that keeps the gutter width when the window narrows.")),
        ]
    }

    static func session(_ state: String, in app: AppModel) -> SessionModel? {
        var configOptions = ComposerPreviewFixtures.configOptions
        for index in configOptions.indices where configOptions[index].category == "model" {
            if case .select(_, var models) = configOptions[index].kind, !models.isEmpty {
                models[0].value = "haiku"
                models[0].name = "Haiku 5.5"
                models[0].description = nil
                configOptions[index].kind = .select(currentValue: "haiku", options: models)
            }
        }
        guard
            let session = SessionModel.preview(
                in: app, title: "Wrap diff lines at word boundaries",
                configOptions: configOptions)
        else {
            return nil
        }
        let quotes = quotes(task: session.clientID)
        if ["C4", "C5", "C7", "C8", "C11", "C13"].contains(state) {
            session.draft = PromptQuote.draft(quotes: quotes, message: "")
        }
        if ["C3", "C12"].contains(state), let first = quotes.first {
            session.beginDiffComment(first)
        }
        if state == "C11" {
            var policy = NativePolicy()
            policy.sourceExcerptsSendingEnabled = false
            policy.organizationName = "Northwind Federal IT"
            policy.organizationContact = "mailto:it@example.invalid"
            session.diffCommentsPolicy = { policy }
        }
        if state == "C5" { session.reviewDiffComments() }
        if state == "C8" { session.diffCommentStatus = "Couldn’t send. Your 2 comments are kept." }
        if state == "C13" {
            session.unresolvedCommentPacket = session.draft
            session.diffCommentSending = true
            session.diffCommentStatus = "Checking whether your comments arrived…"
        }
        if state == "C9", var first = quotes.first {
            first.comment = nil
            session.draft = PromptQuote.draft(
                quotes: [first], message: "Why is fixedSize needed here?")
        }
        if state == "C6" {
            session.previewExchange(
                PromptQuote.draft(quotes: quotes, message: ""), reply: "I’ll update the wrapping and add the test.")
        }
        return session
    }
}
#endif
