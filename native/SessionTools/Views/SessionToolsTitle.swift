import SessionTools
import SwiftUI

/// The session's title and, under it in place of a subtitle, the task's live facts: its branch,
/// then each tool that has something to say ("2 files +12 −3", "Dev :3000", "Cursor"). Only true
/// facts show, so a quiet task has a quiet header, and each fact is the way into its tool.
struct SessionToolsTitle: View {
    let title: String
    /// Where the task is: its branch, else its folder.
    let location: String
    let facts: [(tool: SessionToolContribution, fact: SessionToolFact)]
    let isOpen: (SessionToolContribution) -> Bool
    let action: (SessionToolContribution) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DSInlineCode.plain(title))
                .font(.dsCalloutSemibold)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(1)
            HStack(spacing: DS.Space.xxs) {
                Text(location)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.trailing, DS.Space.xs)
                ForEach(facts, id: \.tool.id) { item in
                    Text("·")
                        .foregroundStyle(.dsTextQuaternary)
                    SessionToolFactButton(tool: item.tool, fact: item.fact, isOpen: isOpen(item.tool)) {
                        action(item.tool)
                    }
                }
            }
            .font(.dsCaption)
        }
        // Where the window draws its own title.
        .padding(.leading, DS.Space.xl)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Facts - Changes and long branch") {
    DSPreviewPair { SessionToolsPreviewFixtures.title().frame(width: 420) }
}
#Preview("Facts - No tools or every tool off") {
    DSPreviewPair { SessionToolsPreviewFixtures.title(hasChanges: false).frame(width: 280) }
}
#endif
