import ACP
import SwiftUI

/// What a tool row's detail panel shows, per the presentation's body style. Long output shows its
/// useful end (`ToolOutputExcerpt`): a command's last lines, a file's or a search's first.
struct ToolCallBody: View {
    let call: ToolCallState
    let presentation: ToolPresentation

    private var phase: ToolPhase { presentation.phase }

    var body: some View {
        let artifacts = call.artifacts
        VStack(alignment: .leading, spacing: 0) {
            output(hasArtifacts: !artifacts.isEmpty)
            if !artifacts.isEmpty {
                FlowLayout(spacing: DS.Space.sm) {
                    ForEach(artifacts.indices, id: \.self) { index in
                        ArtifactThumbnail(artifact: artifacts[index])
                    }
                }
                .padding(DS.Space.lg)
            }
        }
        .composerQuoteSource(ComposerQuoteSource(name: call.title, text: ToolOutput.text(of: call)))
    }

    @ViewBuilder private func output(hasArtifacts: Bool) -> some View {
        switch presentation.body {
        case .command(let command):
            // While a command runs Claude Code puts its description in the content, not output; what
            // a command has printed so far (Codex's chunks) is output.
            CommandOutput(
                command: command, output: phase == .running ? ToolOutput.printed(by: call) : ToolOutput.text(of: call),
                phase: phase)
        case .mcp(let rawName):
            MCPOutput(
                rawName: rawName, input: call.mcpArguments,
                output: ToolOutput.text(of: call) ?? ToolOutput.mcpResult(of: call),
                phase: phase, hasArtifacts: hasArtifacts)
        case .lines:
            if let output = ToolOutput.text(of: call) {
                ToolOutputText(output: output, keeping: .start)
            } else {
                GenericOutput(call: call)
            }
        case .diff where call.content.contains(where: \.isDiff):
            VStack(spacing: 0) {
                ForEach(call.content.indices, id: \.self) { index in
                    if case .diff(let diff) = call.content[index] {
                        if index > 0 { Divider() }
                        DiffView(diff: diff, isEmbedded: true)
                    }
                }
            }
        case .diff, .generic:
            GenericOutput(call: call)
        }
    }
}

enum ToolOutput {
    /// The text the tool produced: its text content without an enclosing code fence, else what the
    /// command printed, else a string `rawOutput`, without the tags an agent wraps errors in for its
    /// model (`ToolErrorMarkup`).
    static func text(of call: ToolCallState) -> String? {
        let texts = call.content.compactMap { content -> String? in
            guard case .content(let block) = content, let text = block.text else { return nil }
            return ToolErrorMarkup.stripped(text.unfenced ?? text)
        }
        if !texts.isEmpty { return texts.joined(separator: "\n") }
        return printed(by: call) ?? call.rawOutput?.stringValue.map(ToolErrorMarkup.stripped)
    }

    /// What an MCP tool returned (`mcpResultText`), likewise without error tags.
    static func mcpResult(of call: ToolCallState) -> String? {
        call.mcpResultText.map(ToolErrorMarkup.stripped)
    }

    /// What a command printed, from the chunks its agent streams (Codex), without the newline that
    /// ends it, which would draw as an empty last line.
    static func printed(by call: ToolCallState) -> String? {
        guard var output = call.terminalOutput else { return nil }
        while output.last?.isNewline == true { output.removeLast() }
        return output.isEmpty ? nil : output
    }

    /// The first line of what a failed call printed or returned, which is usually why it failed.
    static func failureHint(of call: ToolCallState) -> String? {
        let output = text(of: call) ?? mcpResult(of: call)
        return output?
            .split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("```") }
    }

    static func copyText(command: String, call: ToolCallState) -> String {
        let output = ToolPhase(call) == .running ? nil : text(of: call)
        return (["$ \(command)"] + [output].compactMap(\.self)).joined(separator: "\n")
    }
}

/// `$ command` with the prompt dimmed, then its output: the last of it when there's a lot, since
/// that's where the result and the error are.
private struct CommandOutput: View {
    let command: String
    let output: String?
    let phase: ToolPhase

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text("\(Text(verbatim: "$").foregroundStyle(.dsTextTertiary)) \(Text(verbatim: command))")
                .toolOutputType()
            if let output, !output.isEmpty {
                ToolOutputText(output: output, keeping: .end, isPadded: false)
            } else if phase == .running {
                Text("Waiting for command output…")
                    .foregroundStyle(.dsTextTertiary)
                    .toolOutputType()
            }
        }
        .toolOutputPadding()
    }
}

/// Output as plain monospaced text, cut to `ToolOutputExcerpt` with a note of what's left out and
/// a way to copy all of it.
private struct ToolOutputText: View {
    let output: String
    let keeping: ToolOutputExcerpt.End
    var color: Color = .dsTextSecondary
    /// Whether it pads itself inside the panel, or sits in a block that does.
    var isPadded = true

    var body: some View {
        let excerpt = ToolOutputExcerpt(output, keeping: keeping)
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if keeping == .end, let note = excerpt.note { ToolOutputExcerptNote(note: note, output: output) }
            Text(verbatim: excerpt.text)
                .foregroundStyle(color)
                .toolOutputType()
            if keeping == .start, let note = excerpt.note { ToolOutputExcerptNote(note: note, output: output) }
        }
        .toolOutputPadding(isPadded)
    }
}

/// "Showing the last 400 of 12,345 lines", with Copy All.
private struct ToolOutputExcerptNote: View {
    let note: String
    let output: String

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Text(note)
                .foregroundStyle(.dsTextTertiary)
            Button("Copy All") { DSPasteboard.copy(output) }
                .buttonStyle(.ds(.ghost))
                .help("Copy the whole output")
            Spacer(minLength: 0)
        }
        .font(.dsCaption)
    }
}

/// The tool's name as the agent sent it, the call's input as JSON, a hairline, then its output or
/// a word on why there's none yet.
private struct MCPOutput: View {
    let rawName: String
    let input: JSONValue?
    let output: String?
    let phase: ToolPhase
    let hasArtifacts: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: rawName)
                .foregroundStyle(.dsTextTertiary)
                .monospacedOutput()
            Divider()
            if let input, input != .null, !input.isEmptyObject {
                Text(verbatim: input.prettyPrinted())
                    .foregroundStyle(.dsTextSecondary)
                    .monospacedOutput()
                Divider()
            }
            if let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ToolOutputText(
                    output: output, keeping: .start, color: phase == .failed ? Color.dsDanger : .dsTextSecondary)
            } else if !hasArtifacts {
                Text(placeholder)
                    .foregroundStyle(phase == .failed ? Color.dsDanger : .dsTextTertiary)
                    .monospacedOutput()
            }
        }
    }

    private var placeholder: LocalizedStringKey {
        switch phase {
        case .awaitingApproval: "Output will appear here once you approve"
        case .running: "Running…"
        case .failed: "Tool call failed"
        case .rejected: "Not run"
        case .completed, .cancelled, .interrupted, .unreported: "No output"
        }
    }
}

/// Content blocks as sent: fenced output as plain monospaced text, anything else as Markdown.
/// Without content, what the command printed stands in (Codex's file listings and searches), else
/// the raw input.
private struct GenericOutput: View {
    let call: ToolCallState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if call.content.isEmpty, let output = ToolOutput.printed(by: call) {
                ToolOutputText(output: output, keeping: .start)
            } else if call.content.isEmpty, let rawInput = call.rawInput {
                ToolOutputText(output: rawInput.prettyPrinted(), keeping: .start)
            }
            ForEach(call.content.indices, id: \.self) { index in
                ContentBlockView(content: call.content[index])
            }
        }
    }
}

private struct ContentBlockView: View {
    let content: ToolCallContent

    var body: some View {
        switch content {
        case .content(.image), .content(.resourceLink), .content(.resource), .content(.resourceBlob):
            EmptyView()
        case .content(let block):
            if let text = block.text.map(ToolErrorMarkup.stripped) {
                if let code = text.unfenced.map(ToolErrorMarkup.stripped) {
                    ToolOutputText(output: code, keeping: .start)
                } else if text.utf8.count > ToolOutputExcerpt.maxCharacters {
                    // Too long to lay out as Markdown in a row's panel.
                    ToolOutputText(output: text, keeping: .start)
                } else {
                    MarkdownView(text)
                        .font(.dsBody)
                        .padding(DS.Space.lg)
                }
            } else if case .resource(let uri, _, _) = block {
                placeholder(uri, systemImage: "doc")
            } else {
                placeholder("Unsupported content", systemImage: "questionmark.square.dashed")
            }
        case .diff(let diff):
            DiffView(diff: diff, isEmbedded: true)
        case .terminal:
            placeholder("Terminal output isn't shown yet", systemImage: "terminal")
        case .unsupported(let type):
            placeholder("Unsupported content (\(type))", systemImage: "questionmark.square.dashed")
        }
    }

    private func placeholder(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.dsCaption)
            .foregroundStyle(.dsTextSecondary)
            .padding(DS.Space.lg)
    }
}

private extension View {
    /// Tool output type: small monospaced text with roomy lines, padded inside the detail panel.
    func monospacedOutput() -> some View {
        toolOutputType().toolOutputPadding()
    }

    func toolOutputType() -> some View {
        codeTextStyle(.compact)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder func toolOutputPadding(_ isPadded: Bool = true) -> some View {
        if isPadded {
            padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.md)
        } else {
            self
        }
    }
}

private extension ToolCallContent {
    var isDiff: Bool {
        if case .diff = self { true } else { false }
    }
}

private extension String {
    /// The body of a text that is exactly one fenced code block, like Claude Code's tool output.
    var unfenced: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```"), trimmed.count > 6 else { return nil }
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 else { return nil }
        lines.removeFirst()
        lines.removeLast()
        // A fence line inside means several blocks with prose between them; leave that to Markdown.
        guard !lines.contains(where: { $0.hasPrefix("```") }) else { return nil }
        return lines.joined(separator: "\n")
    }
}

#if DEBUG
#Preview("Tool output - Image and artifact") {
    let json = """
        {"toolCallId":"read-image","title":"Read diagram.png","kind":"read","status":"completed",
        "content":[{"type":"content","content":{"type":"image","mimeType":"image/png",
        "data":"\(ArtifactPreviewFixtures.imageData.base64EncodedString())"}}]}
        """
    return DSPreviewPair {
        if let update = SessionModel.previewDecode(ToolCallUpdate.self, json) {
            let call: ToolCallState? = {
                var state = SessionState()
                state.apply(.toolCall(update))
                if case .toolCall(let call) = state.items.first { return call }
                return nil
            }()
            if let call {
                ToolCallBody(call: call, presentation: ToolPresentation(call))
                    .environment(\.openTranscriptArtifact, TranscriptArtifactOpener(session: nil, filesAreLocal: true))
                    .frame(width: 440)
            }
        }
    }
}
#endif
