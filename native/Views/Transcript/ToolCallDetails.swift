import ACP
import SwiftUI

/// What a tool row's detail panel shows, per the presentation's body style.
struct ToolCallBody: View {
    let call: ToolCallState
    let presentation: ToolPresentation
    let phase: ToolPhase

    var body: some View {
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
                phase: phase)
        case .lines:
            if let output = ToolOutput.text(of: call) {
                Text(verbatim: output)
                    .foregroundStyle(.dsTextSecondary)
                    .monospacedOutput()
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

/// `$ command` with the prompt dimmed, then the output.
private struct CommandOutput: View {
    let command: String
    let output: String?
    let phase: ToolPhase

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text("\(Text(verbatim: "$").foregroundStyle(.dsTextTertiary)) \(Text(verbatim: command))")
            if let output, !output.isEmpty {
                Text(verbatim: output)
                    .foregroundStyle(.dsTextSecondary)
            } else if phase == .running {
                Text("Waiting for command output…")
                    .foregroundStyle(.dsTextTertiary)
            }
        }
        .monospacedOutput()
    }
}

/// The tool's name as the agent sent it, the call's input as JSON, a hairline, then its output or
/// a word on why there's none yet.
private struct MCPOutput: View {
    let rawName: String
    let input: JSONValue?
    let output: String?
    let phase: ToolPhase

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
                Text(verbatim: output)
                    .foregroundStyle(phase == .failed ? Color.dsDanger : .dsTextSecondary)
                    .monospacedOutput()
            } else {
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
        case .completed, .cancelled: "No output"
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
                Text(verbatim: output)
                    .foregroundStyle(.dsTextSecondary)
                    .monospacedOutput()
            } else if call.content.isEmpty, let rawInput = call.rawInput {
                Text(verbatim: rawInput.prettyPrinted())
                    .foregroundStyle(.dsTextSecondary)
                    .monospacedOutput()
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
        case .content(.image(let data, let mimeType)):
            if let image = Data(base64Encoded: data).flatMap(Image.init(decoding:)) {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: TranscriptMetrics.toolImageMaxHeight, alignment: .leading)
                    .clipShape(.rect(cornerRadius: DS.Radius.row))
                    .padding(DS.Space.lg)
            } else {
                placeholder("Image (\(mimeType))", systemImage: "photo")
            }
        case .content(.resourceLink(let uri, let name)):
            placeholder(name.isEmpty ? uri : name, systemImage: "link")
        case .content(let block):
            if let text = block.text.map(ToolErrorMarkup.stripped) {
                if let code = text.unfenced.map(ToolErrorMarkup.stripped) {
                    Text(verbatim: code)
                        .foregroundStyle(.dsTextSecondary)
                        .monospacedOutput()
                } else {
                    MarkdownView(text)
                        .font(.dsBody)
                        .padding(DS.Space.lg)
                }
            } else if case .resource(let uri, _) = block {
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
        codeTextStyle(.compact)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.md)
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
