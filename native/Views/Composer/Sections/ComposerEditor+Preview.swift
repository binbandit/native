import ACP
import SwiftUI

#if DEBUG
#Preview("Editor") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ComposerSurface {
                ComposerEditorPreview(text: "", placeholder: "What should Claude Code work on?")
            }
            ComposerSurface {
                ComposerEditorPreview(
                    text: """
                        The queue test still flakes. Look at `PromptQueueTests` and fix the ordering:

                        ```swift
                        queue.move(id, .up)
                        ```
                        """,
                    placeholder: "")
            }
        }
        .frame(width: 560)
    }
}

#Preview("Editor - Live references, unknown counts and narrow") {
    DSPreviewPair {
        ComposerSurface {
            ComposerEditorPreview(
                text: "Check @Packages/ACP/PromptQueue.swift and @\"folder/File with spaces.swift\" please.",
                placeholder: "Message Codex", referencesEnabled: true,
                referenceCounts: ["Packages/ACP/PromptQueue.swift": .init(added: 6, removed: 2)])
        }.frame(width: 380)
    }
}

#Preview("Editor - Dropping files keeps the draft") {
    DSPreviewPair {
        ComposerSurface(isDropTargeted: true) {
            ComposerAttachmentsSection(
                attachments: ComposerPreviewFixtures.attachments, pending: [], missing: [], selected: nil,
                capabilities: PromptCapabilities(image: true), agentName: "Claude Code", onRemove: { _ in })
            ComposerEditorPreview(text: "Review these files, then explain the change.", placeholder: "")
        }
        .frame(width: 560)
    }
}

/// Holds the editor's text, selection and focus, which a preview can't pass as plain values.
private struct ComposerEditorPreview: View {
    @State var text: String
    let placeholder: String
    var referencesEnabled = false
    var referenceCounts: [String: FileReferenceProjection.Counts] = [:]
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    var body: some View {
        ComposerEditor(
            text: $text, selection: $selection, placeholder: placeholder, isFocused: $isFocused,
            referencesEnabled: referencesEnabled, referenceCounts: referenceCounts, routesFileDropsToAttachments: true
        ) { _ in
            .ignored
        }
    }
}
#endif
