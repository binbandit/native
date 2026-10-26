#if DEBUG
import Experiments
import SwiftUI

struct DiffCommentsPreviewHost<Content: View>: View {
    let content: (SessionModel) -> Content
    let state: String
    @State private var fixture: DiffCommentsFixtureModel?

    init(_ state: String = "C5", @ViewBuilder content: @escaping (SessionModel) -> Content) {
        self.state = state
        self.content = content
    }

    var body: some View {
        Group {
            if let fixture, let session = fixture.session {
                content(session).environment(\.experimentStore, fixture.experiments).environment(fixture.app)
                    .environment(
                        BuiltInPlugins.automation.center
                    )
                    .environment(\.diffCommentsSession, session)
            } else {
                Color.dsBackground
            }
        }
        .task { if fixture == nil { fixture = DiffCommentsFixtureModel(state, populated: false) } }
    }
}
#endif
