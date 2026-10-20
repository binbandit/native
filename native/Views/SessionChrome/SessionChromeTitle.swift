#if DEBUG
import SwiftUI

/// The header's title, and under it, in place of a subtitle, the task's live facts (direction C,
/// and D's header place): the branch, what changed, what's running, where it opens. Each is data,
/// and each opens its tool in place. Only true facts show, so a quiet task has a quiet header.
struct SessionChromeTitle: View {
    let title: String
    /// What the subtitle said, shown while no header tool has a fact to give.
    let subtitle: String
    let context: SessionChromeContext
    let chrome: SessionChromeModel

    var body: some View {
        let tools = chrome.arrangement.tools(in: .header).filter { tool in
            tool == .pullRequest ? context.branchName != nil : context.fact(for: tool).isLive
        }
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.dsCalloutSemibold)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(1)
            HStack(spacing: DS.Space.xxs) {
                if !tools.contains(.pullRequest), let branch = context.branchName {
                    plain(branch)
                    separator
                } else if tools.isEmpty {
                    plain(subtitle)
                }
                ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                    if index > 0 {
                        separator
                    }
                    if tool == .openIn {
                        SessionChromeOpenInControl(location: context.openIn, showsName: true)
                    } else {
                        SessionChromeFactButton(
                            tool: tool, fact: context.fact(for: tool), isOpen: chrome.tool(in: .header) == tool
                        ) {
                            withAnimation(.dsPanel) { chrome.toggle(tool) }
                        }
                    }
                }
            }
            .font(.dsCaption)
        }
        // Where the window puts its own title.
        .padding(.leading, DS.Space.xl)
        .fixedSize()
    }

    private var separator: some View {
        Text("·")
            .font(.dsCaption)
            .foregroundStyle(.dsTextQuaternary)
    }

    private func plain(_ text: String) -> some View {
        Text(text)
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.xs)
    }
}

/// One fact in the header: its glyph and data, a hover wash, and selected while its tool is open.
struct SessionChromeFactButton: View {
    let tool: SessionChromeTool
    let fact: SessionChromeFact
    let isOpen: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: tool.systemImage)
                    .font(.dsMicro)
                Text(fact.text)
                    .lineLimit(1)
                SessionChromeFactBadge(fact: fact)
            }
            .font(.dsCaption)
            .foregroundStyle(isOpen || isHovered ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, DS.Space.xs)
            .frame(height: DS.Size.statusGlyph + DS.Space.xs)
            .background(
                isOpen ? Color.dsSelected : isHovered ? Color.dsHover : .clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(.rect)
            .dsHitTarget(DS.Size.controlXS)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .trackHover($isHovered)
        .help(isOpen ? "Close \(tool.title)" : tool.help)
        .accessibilityLabel("\(tool.title): \(fact.text)")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }
}
#endif
