import NativeSetup
import SwiftUI

/// A task that couldn't start, in the approval's frame above its kept message: what failed, the
/// line the agent stopped at when it named one, and the change that fixes it when Native can offer
/// one. Hosts supply the failure and the actions; this view reads and changes nothing itself.
struct AgentStartFailureView: View {
    enum Recovery: Equatable {
        /// Start the task again; `restarts` when the agent's process must restart first.
        case retry(restarts: Bool)
        case signIn
        /// No worktree can be made, but the project folder can take the task.
        case projectFolder
    }

    /// What happens to the message under the card.
    enum Draft: Equatable {
        case none
        case kept
        /// The user sent it; it goes out once the task is running.
        case waiting
    }

    let agentName: String
    let title: String
    /// The agent's own report, shown on request.
    let output: String
    var explanation: String?
    let diagnostic: AgentStartDiagnostic?
    /// The diagnostic's file as the user knows it: "~/.codex/config.toml".
    var displayPath: String?
    var source: [AgentStartDiagnostic.SourceLine] = []
    var fixIt: AgentStartFixIt?
    let recovery: Recovery
    var draft = Draft.none
    var fixFailure: String?
    var isWorking = false
    var initiallyShowsOutput = false
    let onRecover: () -> Void
    var onRetry: () -> Void = {}
    let onFix: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showsOutput: Bool?

    private var isOutputShown: Bool { showsOutput ?? initiallyShowsOutput }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: DS.Approval.failureIcon * 0.875))
                    .foregroundStyle(.dsDanger)
                    .frame(width: DS.Approval.failureIcon, height: DS.Approval.failureIcon)
                    .accessibilityHidden(true)
                Text(title).font(DS.Approval.titleFont).foregroundStyle(.dsTextPrimary)
            }
            .accessibilityAddTraits(.isHeader)
            if let text = explanation
                ?? Self.explanation(agentName: agentName, diagnostic: diagnostic, recovery: recovery, draft: draft)
            {
                Text(text).font(.dsBody).foregroundStyle(.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, DS.Approval.failureIndent)
                    .padding(.top, DS.Approval.failureDetailTop)
            }
            if let diagnostic {
                sourceWell(diagnostic)
                    .padding(.leading, DS.Approval.failureIndent)
                    .padding(.top, DS.Approval.sourceTop)
            }
            if isOutputShown {
                outputWell
                    .padding(.leading, DS.Approval.failureIndent)
                    .padding(.top, DS.Space.md)
            }
            footer.padding(.top, DS.Approval.failureFooterTop)
            if let fixFailure {
                Text(fixFailure).font(.dsBody).foregroundStyle(.dsDanger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, DS.Approval.failureIndent)
                    .padding(.top, DS.Space.md)
            }
        }
        .padding(.horizontal, DS.Approval.inset)
        .padding(.top, DS.Space.xl)
        .padding(.bottom, DS.Approval.askTop)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isWorking)
    }

    /// Why the task stopped and what happens to the user's message, when the host has no words of
    /// its own.
    static func explanation(
        agentName: String, diagnostic: AgentStartDiagnostic?, recovery: Recovery, draft: Draft
    ) -> String? {
        let reason =
            diagnostic.map { "It stopped while reading \($0.fileName)." }
            ?? (recovery == .retry(restarts: true)
                ? "\(agentName) stopped, so it restarts before the task starts again." : nil)
        let message: String? =
            switch draft {
            case .none: nil
            case .kept: "Your message below is kept."
            case .waiting: "Your message below is kept and goes out once \(agentName) is running."
            }
        let parts = [reason, message].compactMap(\.self)
        return parts.isEmpty ? "Anything already set up for the task is kept." : parts.joined(separator: " ")
    }

    // MARK: - Source

    private func sourceWell(_ diagnostic: AgentStartDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(source.isEmpty ? "\(path(diagnostic)), line \(diagnostic.line)" : path(diagnostic))
                .font(.dsMonoCaption).foregroundStyle(.dsTextTertiary)
                .padding(.leading, DS.Approval.commandInset)
                .padding(.bottom, DS.Space.xs)
                .textSelection(.enabled)
            ForEach(source) { line in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: "\(line.number)")
                        .font(.dsMonoCaption).foregroundStyle(.dsTextQuaternary)
                        .frame(width: DS.Approval.lineNumberWidth - DS.Approval.commandInset, alignment: .trailing)
                        .padding(.trailing, DS.Approval.commandInset)
                        .accessibilityLabel("Line \(line.number)")
                    sourceText(line, diagnostic: diagnostic)
                }
                .frame(minHeight: DS.Approval.commandLine)
            }
            Text(diagnostic.message)
                .font(DS.Approval.fixItFont).foregroundStyle(.dsDanger)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.leading, source.isEmpty ? DS.Approval.commandInset : DS.Approval.lineNumberWidth)
                .padding(.trailing, DS.Approval.commandInset)
        }
        .padding(.vertical, DS.Approval.sourceInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Approval.well(colorScheme), in: .rect(cornerRadius: DS.Radius.control))
    }

    private func path(_ diagnostic: AgentStartDiagnostic) -> String {
        displayPath ?? diagnostic.path
    }

    @ViewBuilder
    private func sourceText(_ line: AgentStartDiagnostic.SourceLine, diagnostic: AgentStartDiagnostic) -> some View {
        if line.isRedacted {
            let hidden = Text(line.text.isEmpty ? "credential hidden" : "value hidden").foregroundStyle(.dsTextTertiary)
            Text(line.text.isEmpty ? "\(hidden)" : "\(Text(verbatim: line.text)) \(hidden)")
                .font(.dsMono).foregroundStyle(.dsTextPrimary)
        } else if line.number == diagnostic.line, let marked = Self.marked(line.text, column: diagnostic.column) {
            Text(
                "\(Text(verbatim: marked.before))\(Text(verbatim: marked.mark).customAttribute(DiagnosticSquiggle()))\(Text(verbatim: marked.after))"
            )
            .font(.dsMono).foregroundStyle(.dsTextPrimary)
            .textRenderer(DiagnosticSquiggleRenderer(color: .dsDanger))
            .textSelection(.enabled)
        } else {
            Text(verbatim: line.text).font(.dsMono).foregroundStyle(.dsTextPrimary).textSelection(.enabled)
        }
    }

    /// The word at the agent's column, or the line's last word when the column is past its end
    /// (an unterminated string), split out to carry the squiggle.
    static func marked(_ text: String, column: Int) -> (before: String, mark: String, after: String)? {
        let characters = Array(text)
        var start = min(column - 1, characters.count)
        if start == characters.count {
            guard let last = characters.lastIndex(where: { !$0.isWhitespace }) else { return nil }
            start = characters[...last].lastIndex(where: \.isWhitespace).map { $0 + 1 } ?? 0
        }
        let end = characters[start...].firstIndex(where: \.isWhitespace) ?? characters.count
        guard start < end else { return nil }
        return (String(characters[..<start]), String(characters[start..<end]), String(characters[end...]))
    }

    private var outputWell: some View {
        HeightCappedScrollView(maxHeight: DS.Approval.outputMaximumHeight) {
            Text(verbatim: output)
                .font(DS.Approval.fixItFont).foregroundStyle(.dsTextSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Approval.commandInset)
                .padding(.vertical, DS.Approval.sourceInset)
        }
        .background(DS.Approval.well(colorScheme), in: .rect(cornerRadius: DS.Radius.control))
        .accessibilityLabel("\(agentName)'s output")
    }

    // MARK: - Footer

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.lg) {
                fixItLine
                Spacer(minLength: DS.Space.lg)
                actions
            }
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                fixItLine
                actions.frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder private var fixItLine: some View {
        if let fixIt {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                Text("Fix-it").font(.dsCaption).foregroundStyle(.dsTextTertiary)
                Text(
                    "Change \(Text(verbatim: "\"\(fixIt.original)\"").font(.dsMono).foregroundStyle(.dsTextTertiary).strikethrough(color: .dsDanger)) to \(Text(verbatim: "\"\(fixIt.replacement)\"").font(.dsMono).foregroundStyle(.dsSuccess))"
                )
                .font(.dsBody).foregroundStyle(.dsTextSecondary)
            }
            .padding(.leading, DS.Approval.failureIndent)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Fix-it: change \(fixIt.original) to \(fixIt.replacement)")
        }
    }

    private var actions: some View {
        HStack(spacing: DS.Space.md) {
            if !output.isEmpty, recovery != .signIn, recovery != .projectFolder {
                Button(isOutputShown ? "Hide Output" : "Show Output") { showsOutput = !isOutputShown }
                    .buttonStyle(ApprovalActionStyle())
                    .keyboardShortcut("o", modifiers: [.command, .option])
                    .help("\(isOutputShown ? "Hide" : "Show") what \(agentName) reported (⌥⌘O)")
            }
            if recovery == .projectFolder {
                Button("Retry", action: onRetry).buttonStyle(ApprovalActionStyle())
            }
            Button(primaryTitle, action: fixIt == nil ? onRecover : onFix)
                .buttonStyle(ApprovalActionStyle(primary: true))
                .keyboardShortcut("r", modifiers: .command)
                .help(primaryHelp)
        }
        .fixedSize()
    }

    private var primaryTitle: String {
        switch recovery {
        case .retry(let restarts) where fixIt != nil: restarts ? "Fix and Restart" : "Fix and Retry"
        case .retry(let restarts): restarts ? "Restart and Retry" : "Retry"
        case .signIn: "Sign In"
        case .projectFolder: "Start in Project Folder"
        }
    }

    private var primaryHelp: String {
        guard let fixIt, let diagnostic else { return "\(primaryTitle) (⌘R)" }
        let file = diagnostic.fileName
        return
            "Changes \"\(fixIt.original)\" to \"\(fixIt.replacement)\" in \(file), keeps the original as \(file).native-backup, and starts the task again (⌘R)"
    }
}

#if DEBUG
#Preview("Failed start - fix-it, no fix, syntax, output, fix failed, remote, sign in") {
    DSPreviewPair {
        ScrollView {
            VStack(spacing: DS.Space.xl) {
                ApprovalSurface { AskPreviewFixtures.failure() }
                ApprovalSurface { AskPreviewFixtures.failure(canFix: false, recovery: .retry(restarts: true)) }
                ApprovalSurface {
                    AskPreviewFixtures.failure(
                        AskPreviewFixtures.unterminated,
                        source: [.init(number: 2, text: "model = \"gpt-6.1-sol", isRedacted: false)], draft: .kept)
                }
                ApprovalSurface {
                    AskPreviewFixtures.failure(
                        "Codex exited.\n\nerror: unexpected argument '--acp' found", showsOutput: true)
                }
                ApprovalSurface {
                    AskPreviewFixtures.failure(
                        fixFailure:
                            "config.toml changed since the agent read it, so nothing was changed. Retry to read it again."
                    )
                }
                ApprovalSurface { AskPreviewFixtures.failure(source: [], canFix: false) }
                ApprovalSurface {
                    AgentStartFailureView(
                        agentName: "Codex", title: "Codex needs you to sign in", output: "",
                        explanation: "Sign in, and the task starts with what you've written.", diagnostic: nil,
                        recovery: .signIn, onRecover: {}, onFix: {})
                }
                ApprovalSurface { AskPreviewFixtures.failure() }.frame(width: 420)
            }
            .frame(width: 808)
            .padding(DS.Space.xl)
        }
        .frame(height: 900)
    }
}
#endif
