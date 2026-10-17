import ACP
import SwiftUI

/// A user prompt, an agent reply, or the agent's reasoning.
struct MessageView: View {
    let message: TranscriptMessage

    var body: some View {
        switch message.role {
        case .user:
            TrailingFractionLayout(fraction: 0.85) {
                // Prompts are shown as typed; Markdown syntax in them stays literal.
                Text(verbatim: message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 16, style: .continuous))
            }
        case .agent:
            MarkdownView(message.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .thought:
            ThoughtView(text: message.text)
        }
    }
}

struct NoticeView: View {
    let notice: TranscriptNotice

    var body: some View {
        Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "info.circle")
            .font(.subheadline)
            .foregroundStyle(notice.isError ? Color.red : Color.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
    }
}

/// The agent's reasoning, collapsed behind a "Thinking" disclosure.
private struct ThoughtView: View {
    let text: String

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text("Thinking")
                    DisclosureChevron(isExpanded: isExpanded)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                MarkdownView(text)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.quaternary)
                            .frame(width: 2)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Fills the offered width and trailing-aligns its content, which gets at most `fraction` of it.
private struct TrailingFractionLayout: Layout {
    let fraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(childProposal(for: proposal))
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let childProposal = childProposal(for: ProposedViewSize(bounds.size))
        let size = child.sizeThatFits(childProposal)
        child.place(at: CGPoint(x: bounds.maxX, y: bounds.minY), anchor: .topTrailing, proposal: ProposedViewSize(size))
    }

    private func childProposal(for proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width.map { $0 * fraction }, height: nil)
    }
}

#if DEBUG
#Preview("Messages") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(TranscriptFixtures.messages, id: \.id) { message in
                MessageView(message: message)
            }
            ForEach(TranscriptFixtures.notices, id: \.id) { notice in
                NoticeView(notice: notice)
            }
        }
        .padding(20)
    }
    .frame(width: 640, height: 640)
}
#endif
