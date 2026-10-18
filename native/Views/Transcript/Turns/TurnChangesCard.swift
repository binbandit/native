import ACP
import SwiftUI

/// After the latest turn that changed files: "7 files changed +120 −14", the files a click away,
/// and the next steps for them, Review (the changes inspector, ⌘⇧D) and Commit, as quiet buttons.
struct TurnChangesCard: View {
    let summary: TurnSummary

    @Environment(\.turnChangesActions) private var actions
    @State private var showsFiles = false
    @State private var isCommitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if showsFiles {
                SeparatorLine()
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(summary.changedFiles, id: \.path) { file in
                        fileRow(file)
                    }
                }
                .padding(.vertical, DS.Space.xs)
                .transition(RevealTransition())
            }
        }
        .background(.dsHover, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(.dsSeparator)
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            Button {
                withAnimation(.reveal) { showsFiles.toggle() }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "doc.on.doc")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.dsTextTertiary)
                        .frame(width: DS.Size.rowLeading)
                    Text(Self.title(for: summary))
                        .font(.dsCalloutMedium)
                        .foregroundStyle(.dsTextPrimary)
                    DiffStatsText(stats: DiffStats(added: summary.linesAdded, removed: summary.linesRemoved))
                        .font(.dsBody)
                    DisclosureChevron(isExpanded: showsFiles)
                    Spacer(minLength: DS.Space.md)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(showsFiles ? "Hides the files" : "Lists the files")

            if let actions {
                Button("Review", action: actions.review)
                    .buttonStyle(.ds(.ghost))
                    .help("Review the changes (⌘⇧D)")
                if let commitForm = actions.commitForm {
                    Button("Commit") { isCommitting = true }
                        .buttonStyle(.ds(.ghost))
                        .help("Commit the changes")
                        .popover(isPresented: $isCommitting, arrowEdge: .bottom) {
                            commitForm($isCommitting)
                        }
                }
            }
        }
        .padding(.leading, DS.Space.md)
        .padding(.trailing, DS.Space.sm)
        .frame(minHeight: DS.Size.controlMD)
    }

    private func fileRow(_ file: TurnSummary.ChangedFile) -> some View {
        HStack(spacing: DS.Space.sm) {
            Text(URL(filePath: file.path).lastPathComponent)
                .foregroundStyle(.dsTextSecondary)
            Text(URL(filePath: file.path).deletingLastPathComponent().abbreviatedPath)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: DS.Space.md)
            DiffStatsText(stats: DiffStats(added: file.added, removed: file.removed))
        }
        .font(.dsBody)
        .padding(.leading, DS.Space.md + DS.Size.rowLeading + DS.Space.sm)
        .padding(.trailing, DS.Space.md)
        .frame(minHeight: DS.Size.listRow)
        .textSelection(.enabled)
    }

    /// "1 file changed", "7 files changed".
    static func title(for summary: TurnSummary) -> String {
        summary.changedFiles.count == 1 ? "1 file changed" : "\(summary.changedFiles.count) files changed"
    }
}

/// What the files-changed card can do with a turn's changes. The session view provides it, so the
/// transcript never depends on the Git feature.
struct TurnChangesActions {
    /// Opens the changes inspector.
    var review: () -> Void
    /// The commit form, shown from the card's Commit button; nil when there's nothing to commit.
    var commitForm: ((Binding<Bool>) -> AnyView)?
}

extension EnvironmentValues {
    /// Next steps for the files-changed card; nil where there are none (a subagent's transcript).
    @Entry var turnChangesActions: TurnChangesActions?
}
