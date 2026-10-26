import Experiments
import SwiftUI

extension View {
    @ViewBuilder func diffCommentsDesignFixture() -> some View {
        #if DEBUG
        if let state = UserDefaults.standard.string(forKey: "nativeDiffCommentsFixture") {
            DiffCommentsDesignFixture(state: state)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
import ACP

struct DiffCommentsDesignFixture: View {
    let state: String
    @State private var fixture: DiffCommentsFixtureModel?

    init(state: String) { self.state = state }

    var body: some View {
        Group {
            if let fixture, let session = fixture.session {
                let app = fixture.app
                HStack(spacing: 0) {
                    AllInViewPreviewList(app: app)
                        .frame(width: DS.Size.sidebarWidth)
                    SeparatorLine(axis: .vertical)
                    VStack(spacing: 0) {
                        HStack {
                            Text("Wrap diff lines at word boundaries").font(.dsHeadline)
                            Spacer()
                            Text("Claude Code").font(.dsCallout).foregroundStyle(.dsTextSecondary)
                        }
                        .padding(DS.Space.xl)
                        SeparatorLine()
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: DS.Space.xl) {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: DS.Space.xl) {
                                        Text("Wrap the diff lines at word boundaries.").font(.dsBody)
                                        Text("The code wraps inside its column. Line numbers stay in their gutter.")
                                            .font(.dsBody).foregroundStyle(.dsTextSecondary)
                                        if state == "C6" {
                                            DiffCommentsTranscriptPacket(
                                                quotes: DiffCommentsPreviewFixtures.quotes(task: session.clientID),
                                                message: "")
                                        }
                                    }
                                    .padding(DS.Space.xl)
                                }
                                ComposerView(session: session)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            SeparatorLine(axis: .vertical)
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Changes").font(.dsHeadline)
                                    Text("This turn").font(.dsCallout).foregroundStyle(.dsTextSecondary)
                                    Spacer()
                                }
                                .padding(.horizontal, DS.Space.xl)
                                .frame(height: DS.TaskWell.changesHeaderHeight)
                                SeparatorLine()
                                if state == "C10" {
                                    EmptyStateView(
                                        "No changes yet", systemImage: "checkmark.circle",
                                        message: "Files appear here after they’re edited."
                                    ) {
                                        Button("Back to Task") { session.wantsComposerFocus = true }
                                            .buttonStyle(.ds(.secondary))
                                    }
                                } else {
                                    VStack(spacing: 0) {
                                        ForEach(["DiffRow.swift", "DiffLayoutTests.swift"], id: \.self) { name in
                                            HStack {
                                                Text("M").font(DS.ComposerQuote.numberFont).foregroundStyle(
                                                    .dsTextTertiary)
                                                Text(name).font(.dsCallout)
                                                Spacer()
                                                DiffStatLabel(
                                                    added: name == "DiffRow.swift" ? 8 : 23,
                                                    removed: name == "DiffRow.swift" ? 5 : 4)
                                            }
                                            .padding(.horizontal, DS.Space.md).frame(height: DS.Size.controlSM)
                                            .background(name == "DiffRow.swift" ? Color.dsSelected : .clear)
                                        }
                                    }.padding(DS.Space.md)
                                    DiffCommentsView(
                                        session: session, path: DiffCommentsPreviewFixtures.path,
                                        oldText: DiffCommentsPreviewFixtures.old,
                                        newText: state == "C7"
                                            ? DiffCommentsPreviewFixtures.new + "\n// Changed again"
                                            : DiffCommentsPreviewFixtures.new,
                                        layout: nil,
                                        initialSelection: ["C2", "C3", "C9", "C12"].contains(state)
                                            ? DiffCommentsPreviewFixtures.quotes(task: session.clientID).first : nil,
                                        initiallyFocusesComment: state == "C2")
                                    DiffCommentsFooter(session: session)
                                }
                            }
                            .frame(width: DS.DiffComments.referencePaneWidth)
                        }
                    }
                }
                .background(.dsBackground)
                .environment(\.experimentStore, fixture.experiments)
                .focusedSceneValue(\.activeSession, session)
                .environment(BuiltInPlugins.automation.center)
                .environment(app)
                .sidebarPreviewEnvironment(app)
                .environment(
                    \.composerQuoteContext,
                    ComposerQuoteContext(
                        task: session.clientID,
                        quotes: session.composerQuotes, selectedSource: session.quoteSelectionSource,
                        select: { session.selectQuote($1, source: $0) }, quote: session.quote,
                        clear: session.clearQuoteSelection))
            } else {
                Color.dsBackground
            }
        }
        .task { if fixture == nil { fixture = DiffCommentsFixtureModel(state) } }
    }
}

#Preview("Diff comments - All states") {
    DSPreviewPair {
        DiffCommentsDesignFixture(state: "C5").frame(width: 1440, height: 900)
    }
}

#Preview("Diff comments - C1") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C1").frame(width: 1440, height: 900) }
}

#Preview("Diff comments - C2") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C2").frame(width: 1440, height: 900) }
}

#Preview("Diff comments - C3") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C3").frame(width: 1440, height: 900) }
}

#Preview("Diff comments - C4") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C4").frame(width: 1440, height: 900) }
}

#Preview("Diff comments - C6") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C6").frame(width: 1440, height: 900) }
}

#Preview("Diff comments - C7") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C7").frame(width: 1440, height: 900) }
}

#Preview("Diff comments - C8") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C8").frame(width: 1440, height: 900) }
}

#Preview("Diff comments - C9") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C9").frame(width: 1440, height: 900) }
}

#Preview("Diff comments - C10") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C10").frame(width: 1440, height: 900) }
}

#Preview("Diff comments - C11") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C11").frame(width: 1440, height: 900) }
}

#Preview("Diff comments - C12") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C12").frame(width: 1440, height: 900) }
}

#Preview("Diff comments - C13") {
    DSPreviewPair { DiffCommentsDesignFixture(state: "C13").frame(width: 1440, height: 900) }
}
#endif
