import ACP
import SwiftUI

/// One transcript item at phone size: the person's messages in bubbles, the agent's as full-width
/// text, tools as one line each (tap for the details), notices (an interruption and what Native did
/// about it) as quiet captions.
struct CompanionTranscriptRow: View {
    let item: TranscriptItem
    let answers: [String: String]
    let openToolCall: (ToolCallState) -> Void

    @State private var showsThought = false

    var body: some View {
        switch item {
        case .message(let message):
            messageRow(message)
        case .toolCall(let call):
            toolCall(call)
        case .notice(let notice):
            Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle" : "info.circle")
                .font(CompanionType.caption)
                .foregroundStyle(notice.isError ? .dsDanger : .dsTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.md)
                .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
        case .subagent(let subagent):
            Label(subagent.title ?? "Subagent", systemImage: "person.2")
                .font(CompanionType.subheadline)
                .foregroundStyle(.dsTextSecondary)
        case .sessionMessage(let message):
            Text(message.text)
                .font(CompanionType.subheadline)
                .foregroundStyle(.dsTextSecondary)
                .padding(DS.Space.md)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.dsBorderStrong).frame(width: TranscriptMetrics.sessionMessageRailWidth)
                }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: TranscriptMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: DS.Space.xxxl)
                Text(message.text)
                    .font(CompanionType.body)
                    .foregroundStyle(.dsTextPrimary)
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.vertical, DS.Space.md)
                    .background(.dsSurface, in: .rect(cornerRadius: TranscriptMetrics.promptBubbleRadius))
                    .textSelection(.enabled)
            }
        case .agent:
            MarkdownView(message.text)
                .font(CompanionType.body)
                .textSelection(.enabled)
        case .thought:
            DisclosureGroup(isExpanded: $showsThought) {
                Text(message.text)
                    .font(CompanionType.subheadline)
                    .foregroundStyle(.dsTextSecondary)
            } label: {
                Text(thoughtTitle(message)).font(CompanionType.subheadline).foregroundStyle(.dsTextTertiary)
            }
        }
    }

    private func thoughtTitle(_ message: TranscriptMessage) -> String {
        guard let start = message.startedAt, let end = message.updatedAt else { return "Thought" }
        return DSFormat.thoughtFor(end.timeIntervalSince(start))
    }

    private func toolCall(_ call: ToolCallState) -> some View {
        let presentation = CompanionToolSummary(call)
        return Button {
            openToolCall(call)
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.md) {
                    Image(systemName: presentation.symbol)
                        .foregroundStyle(call.status == .failed ? .dsDanger : .dsTextTertiary)
                        .frame(width: DS.Size.statusGlyph)
                    Text(presentation.line)
                        .foregroundStyle(.dsTextSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let stats = presentation.stats, stats != DiffStats() {
                        DiffStatsText(stats: stats)
                    }
                }
                .font(CompanionType.subheadline)
                if let answer = answers[call.id] {
                    Text(answer).font(CompanionType.caption).foregroundStyle(.dsTextTertiary)
                }
            }
            .frame(minHeight: DS.Size.minimumHitTarget)
        }
        .buttonStyle(.plain)
    }
}

/// A tool call in full: the command or input, and what came back. View only.
struct ToolCallDetailSheet: View {
    let call: ToolCallState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: DS.Space.sm) {
                            Text(section.title).font(CompanionType.captionMedium).foregroundStyle(.dsTextSecondary)
                            ScrollView(.horizontal) {
                                Text(section.text)
                                    .font(CompanionType.mono)
                                    .foregroundStyle(.dsTextPrimary)
                                    .textSelection(.enabled)
                                    .padding(DS.Space.md)
                            }
                            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card))
                        }
                    }
                    if sections.isEmpty {
                        Text("No details yet.").font(CompanionType.body).foregroundStyle(.dsTextSecondary)
                    }
                }
                .padding(DS.Space.lg)
            }
            .background(.dsBackground)
            .navigationTitle(CompanionToolSummary(call).subject)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var sections: [(title: String, text: String)] {
        var result: [(String, String)] = []
        if let command = call.shellCommand {
            result.append(("Command", command))
        } else if let input = call.rawInput {
            result.append(("Input", input.prettyText))
        }
        for content in call.content {
            switch content {
            case .content(.text(let text)): result.append(("Output", text))
            case .diff(let diff): result.append((diff.path, diff.newText))
            default: break
            }
        }
        if result.count < 2, let output = call.rawOutput {
            result.append(("Output", output.prettyText))
        }
        return result
    }
}

extension JSONValue {
    var prettyText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
