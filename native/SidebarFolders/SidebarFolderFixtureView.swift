#if DEBUG
import SwiftUI

/// Running-app visual fixtures for states a pid-scoped driver cannot create, such as external hover.
struct SidebarFolderFixtureView: View {
    let state: String
    @State private var model: AppModel?

    var body: some View {
        Group {
            if let model {
                HStack(spacing: 0) {
                    SidebarView().frame(width: DS.Size.sidebarWidth)
                    SeparatorLine(axis: .vertical)
                    if state == "F4" || state == "F5" || state == "F10" {
                        SidebarFolderHome(agents: [])
                    } else {
                        VStack(alignment: .leading, spacing: DS.Space.xl) {
                            Text(
                                "Editing a queued message should keep its place. Add a test for editing the first of three messages."
                            )
                            .padding(DS.Space.xl).background(.dsHover, in: .rect(cornerRadius: DS.Radius.message))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(
                                "An edited message now replaces the original entry. It keeps its position in the queue."
                            )
                            Text("The regression test covers editing the first of three queued messages.")
                            Spacer()
                        }
                        .font(.dsCalloutBook).foregroundStyle(.dsTextPrimary)
                        .padding(.top, DS.Space.xxxl)
                        .padding(.horizontal, DS.Space.xxl)
                        .frame(maxWidth: DS.Size.contentColumn, maxHeight: .infinity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.dsBackground)
                    }
                }
                .sidebarPreviewEnvironment(model)
            }
        }
        .task { if model == nil { model = SidebarFolderPreviewFixtures.model(state) } }
    }
}

#Preview("Folders - Managed roots") {
    DSPreviewPair { SidebarFolderFixtureView(state: "F7").frame(width: 1000, height: 700) }
}
#Preview("Folders - Every root forbidden") {
    DSPreviewPair { SidebarFolderFixtureView(state: "blocked").frame(width: 1000, height: 700) }
}
#Preview("Folders - Keyboard focus") {
    DSPreviewPair { SidebarFolderFixtureView(state: "F8").frame(width: 1000, height: 700) }
}
#Preview("Folders - Drop") { DSPreviewPair { SidebarFolderFixtureView(state: "F3").frame(width: 1000, height: 700) } }
#endif
