import AIInstructions
import SwiftUI

/// One purpose's instructions: a multi-line field with an example, Preview and Reset under it, and
/// the preview's result below them. Used on the AI Instructions page and for a project's own.
struct AIInstructionEditor: View {
    let purpose: AIInstructionPurpose
    @Binding var text: String
    /// The prefix new branches get, for previewing branch names.
    var branchPrefix: String
    /// The project whose instructions these are; nil for the global ones.
    var project: URL?

    /// The text Reset cleared, which Undo Reset (in Reset's place) brings back until the user types.
    @State private var resetFrom: String?
    @State private var preview = AIInstructionPreviewState.idle
    @State private var previewTask: Task<Void, Never>?
    @Environment(\.settingsLockReason) private var lockReason

    /// Where the count of characters starts to show.
    private static let countFrom = AIInstructionAddition.maximumLength * 4 / 5

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            TextField(purpose.example, text: limited, axis: .vertical)
                .lineLimit(2...8)
                .padding(.vertical, DS.Space.sm)
                .settingsField()
                .accessibilityLabel("\(purpose.title) instructions")
            HStack(spacing: DS.Space.md) {
                if text.count >= Self.countFrom {
                    Text("\(text.count) of \(AIInstructionAddition.maximumLength) characters")
                        .settingsText(.caption)
                        .foregroundStyle(.dsTextSecondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                if let resetFrom {
                    Button("Undo Reset", systemImage: "arrow.uturn.backward") {
                        text = resetFrom
                        self.resetFrom = nil
                    }
                    .help("Bring back the instructions Reset cleared")
                } else {
                    Button("Reset") {
                        resetFrom = text
                        text = ""
                        preview = .idle
                    }
                    .disabled(text.isEmpty)
                    .help("Clear these instructions")
                }
                Button(preview.isRunning ? "Stop" : "Preview", systemImage: preview.isRunning ? "stop" : "sparkles") {
                    preview.isRunning ? stopPreview() : runPreview()
                }
                .help(previewHelp)
            }
            .buttonStyle(.settings)
            AIInstructionPreviewView(purpose: purpose, state: preview, retry: runPreview) {
                preview = .idle
            }
        }
        .onChange(of: text) { _, newValue in
            if !newValue.isEmpty { resetFrom = nil }
        }
        .onChange(of: lockReason) { _, _ in stopPreview() }
        .onDisappear { previewTask?.cancel() }
    }

    /// The text, never longer than what's sent.
    private var limited: Binding<String> {
        Binding(
            get: { text },
            set: { text = String($0.prefix(AIInstructionAddition.maximumLength)) }
        )
    }

    private var previewHelp: String {
        switch purpose.generator {
        case .onDevice: "Write one for a sample task with these instructions, on this Mac"
        case .agent: "Show what the agent would get for a sample pull request"
        }
    }

    private func runPreview() {
        previewTask?.cancel()
        preview = .running
        let purpose = purpose
        let text = text
        let prefix = branchPrefix
        let project = project
        previewTask = Task {
            do {
                let output = try await AIInstructionPreviewer.preview(
                    purpose, text: text, branchPrefix: prefix, project: project)
                guard !Task.isCancelled else { return }
                preview = .done(output, instructions: text)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                preview = .failed(error.localizedDescription)
            }
        }
    }

    private func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        if preview.isRunning { preview = .idle }
    }
}

/// Where a preview is.
enum AIInstructionPreviewState: Equatable {
    case idle
    case running
    /// What was written, and the instructions it was written with, to say when they've changed since.
    case done(AIInstructionPreviewer.Output, instructions: String)
    case failed(String)

    var isRunning: Bool { self == .running }
}
