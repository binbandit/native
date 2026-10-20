import SwiftUI
import TaskScripts

/// A script's output in a sunken monospace well, selectable, kept scrolled to its newest line while
/// the script runs. `lines` shows only the last few, for a failure's notice.
struct TaskScriptOutputView: View {
    let output: TaskScriptOutput
    var maxHeight = TaskScriptMetrics.outputMaxHeight
    var lines: Int?

    private var text: String {
        let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lines else { return text }
        return output.lastLines(lines).joined(separator: "\n")
    }

    var body: some View {
        if !text.isEmpty {
            CappedHeightScrollView(maxHeight: maxHeight) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    if output.droppedBytes > 0, lines == nil {
                        Text("Earlier output was trimmed.")
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                    Text(verbatim: text)
                        .codeTextStyle(.compact)
                        .foregroundStyle(.dsTextSecondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.sm)
            }
            .defaultScrollAnchor(.bottom)
            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
            .accessibilityLabel("Script output")
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Script output") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            TaskScriptOutputView(output: TaskScriptsPreviewFixtures.succeeded.output)
            TaskScriptOutputView(output: TaskScriptsPreviewFixtures.failed.output, lines: 2)
        }
        .frame(width: 560)
    }
}
#endif
