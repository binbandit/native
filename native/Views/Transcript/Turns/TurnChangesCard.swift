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
                if actions?.isRecordOnly == true {
                    actions?.review()
                } else {
                    withAnimation(.reveal) { showsFiles.toggle() }
                }
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
            .accessibilityHint(
                actions?.isRecordOnly == true ? "Shows Changes" : showsFiles ? "Hides the files" : "Lists the files")

            if let actions, !actions.isRecordOnly {
                Button("Review", action: actions.review)
                    .buttonStyle(.ds(.ghost))
                    .help("Review this turn's changes")
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

    @ViewBuilder private func fileRow(_ file: TurnSummary.ChangedFile) -> some View {
        let row = HStack(spacing: DS.Space.sm) {
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
        if let reviewFile = actions?.reviewFile {
            // Each file opens its own changes in this turn; selecting text would swallow the click.
            Button {
                reviewFile(file.path)
            } label: {
                row.contentShape(.rect)
            }
            .buttonStyle(TurnChangesFileRowStyle())
            .help("Show this file's changes in this turn")
            .accessibilityHint("Shows this file's changes in this turn")
        } else {
            row.textSelection(.enabled)
        }
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
    /// Opens the changes inspector on one file's changes in this turn, by the path the card lists.
    var reviewFile: ((String) -> Void)?
    /// What the latest turn changed as git sees it, whatever made the change; the card lists these
    /// in place of the agent's reported edits, so a turn that edited through the shell gets one too.
    var latestTurnChanges: TurnDetectedChanges?
    /// The well owns Review and the Changes pane owns Commit; the card remains a record.
    var isRecordOnly = false
}

/// A file row that opens its changes: a list row's hover fill, a shade darker while pressed.
private struct TurnChangesFileRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background(configuration.isPressed ? .dsPressed : isHovered ? .dsHover : .clear)
                .trackHover($isHovered)
        }
    }
}

extension EnvironmentValues {
    /// Next steps for the files-changed card; nil where there are none (a subagent's transcript).
    @Entry var turnChangesActions: TurnChangesActions?
}

#if DEBUG
#Preview("Turn changes - Record under the well") {
    DSPreviewPair {
        TurnChangesCard(summary: TurnChangesPreviewFixtures.summary)
            .environment(\.turnChangesActions, TurnChangesActions(review: {}, isRecordOnly: true))
            .frame(width: 460)
    }
}

#Preview("Turn changes - Committed, long paths and binary file") {
    DSPreviewPair {
        TurnChangesCard(summary: TurnChangesPreviewFixtures.summary)
            .environment(\.turnChangesActions, TurnChangesActions(review: {}, reviewFile: { _ in }))
            .frame(width: 460)
    }
}
#endif
