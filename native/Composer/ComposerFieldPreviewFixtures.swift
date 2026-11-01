#if DEBUG
import SwiftUI

enum ComposerFieldPreviewFixtures {
    static func field(
        _ text: String = "", width: CGFloat = DS.ComposerField.previewWidth,
        attachments: Bool = false, working: Bool = false, stopping: Bool = false
    ) -> some View {
        var state = ComposerRowPreviewFixtures.state
        state.isWorking = working
        state.isStopping = stopping
        if working { state.locations = [] }
        state.disabledReason = text.isEmpty && !attachments ? "Write a message or attach a file" : nil
        return ComposerField(
            text: .constant(text), isFocused: .constant(false), openMenu: .constant(nil), state: state,
            actions: .init()
        ) {
            if attachments {
                FlowLayout(spacing: DS.Space.sm) {
                    ComposerChip("ComposerField.swift", systemImage: "doc.text") {}
                    ComposerChip("Layout.png", systemImage: "photo") {}
                    ComposerChip("Comment: keep the row in place", systemImage: "text.bubble") {}
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.md)
            }
        }
        .frame(width: width)
    }
}

#Preview("Composer field - Empty, draft, attachments and growing text") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ComposerFieldPreviewFixtures.field()
            ComposerFieldPreviewFixtures.field("Keep the message field calm and the controls close together.")
            ComposerFieldPreviewFixtures.field("Review the attached layout and comment.", attachments: true)
            ComposerFieldPreviewFixtures.field(
                (1...12).map { "Line \($0): text grows upward, then scrolls after ten lines." }.joined(separator: "\n"))
        }
    }
}

#Preview("Composer field - Narrow, working and labelled stopping") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ComposerFieldPreviewFixtures.field("A narrow new task", width: DS.ComposerField.narrowWidth)
            ComposerFieldPreviewFixtures.field("A follow-up waits in the queue", working: true)
            ComposerFieldPreviewFixtures.field("Keep this draft when stopped", working: true, stopping: true)
        }
    }
}

#Preview("Composer field - File and command lists") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ComposerFieldSuggestions(
                items: [
                    .file("./"), .file("native/"), .file("native/Composer/"),
                    .file("native/Composer/ComposerField.swift"),
                ],
                highlighted: .constant(2), choose: { _ in })
            ComposerFieldSuggestions(
                items: [
                    .command(.init(native: "goal", description: "Manage the task goal")),
                    .command(.init(native: "plan", description: "Plan the next change")),
                    .command(.init(native: "compact", description: "Compact the conversation")),
                ],
                highlighted: .constant(0), choose: { _ in })
        }
        .frame(width: DS.ComposerField.completionWidth)
    }
}

#Preview("Composer field - Attachment failure") {
    DSPreviewPair {
        VStack(spacing: DS.Space.sm) {
            NoticeBanner(tone: .warning, title: "Couldn't attach Layout.png. Try attaching it with Attach Files.")
            ComposerFieldPreviewFixtures.field("Review the layout once I attach it.")
        }
        .frame(width: DS.ComposerField.previewWidth)
    }
}

#Preview("Composer field - Completion above the caret") {
    DSPreviewPair {
        VStack(spacing: 0) {
            Spacer(minLength: ComposerMetrics.suggestionListMaxHeight)
            ComposerField(
                text: .constant("Review @./"), isFocused: .constant(true), openMenu: .constant(nil),
                state: ComposerRowPreviewFixtures.state, actions: .init(),
                files: ["native/", "docs/", "Packages/", "README.md"]
            ) { EmptyView() }
        }
        .frame(width: DS.ComposerField.previewWidth)
    }
}
#endif
