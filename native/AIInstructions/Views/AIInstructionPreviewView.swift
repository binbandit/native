import AIInstructions
import SwiftUI

/// A preview's result under an instruction field: writing, what was written for the sample task (or
/// what the agent would get), or why it couldn't be written. Nothing while there's no preview.
struct AIInstructionPreviewView: View {
    let purpose: AIInstructionPurpose
    let state: AIInstructionPreviewState
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: DS.Space.md) {
                DotGridLoader(pattern: .typing)
                Text("Writing with Apple Intelligence for a sample task…")
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextSecondary)
            }
            .accessibilityElement(children: .combine)
        case .done(let output, _):
            result(output)
        case .failed(let reason):
            ErrorState(
                "Couldn't write a preview", suggestion: reason,
                primary: .init("Try Again", perform: retry), secondary: .init("Dismiss", perform: dismiss))
        }
    }

    private func result(_ output: AIInstructionPreviewer.Output) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Text(caption(for: output))
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextSecondary)
                Spacer(minLength: 0)
                IconButton("Hide Preview", systemImage: "xmark", action: dismiss)
            }
            CappedHeightScrollView(maxHeight: AIInstructionMetrics.previewMaxHeight) {
                text(of: output)
                    .foregroundStyle(.dsTextPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Space.lg)
        .background(.dsSurfaceSunken, in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview")
    }

    private func caption(for output: AIInstructionPreviewer.Output) -> String {
        switch output {
        case .generated: "Written on this Mac for a sample task"
        case .prompt: "What the agent gets for a sample pull request"
        }
    }

    @ViewBuilder
    private func text(of output: AIInstructionPreviewer.Output) -> some View {
        switch output {
        case .generated(let text) where purpose == .title || purpose == .pullRequest:
            Text(text).settingsText(.body)
        case .generated(let text), .prompt(let text):
            Text(text).codeTextStyle(.compact)
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Instruction preview") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            AIInstructionPreviewView(purpose: .title, state: .running, retry: {}, dismiss: {})
            AIInstructionPreviewView(
                purpose: .commitMessage,
                state: .done(
                    .generated("fix(checkout): charge once when the pay button is pressed twice"),
                    instructions: "Conventional commits, under 72 characters."),
                retry: {}, dismiss: {})
            AIInstructionPreviewView(
                purpose: .pullRequest,
                state: .failed("Apple Intelligence is turned off in System Settings, so nothing can be written here."),
                retry: {}, dismiss: {})
        }
        .settingsPreviewPage()
    }
}
#endif
