#if DEBUG
import SessionTools
import SwiftUI

/// The chrome previews use fixed repositories and in-memory sessions, never live Git services.
enum SessionToolsPreviewFixtures {
    static let app = AppModel.preview()
    static let session = SessionModel.preview(in: app)
    static let registry = SessionToolRegistry(defaults: PreviewUserDefaults())
    static let screen = SessionToolsScreenModel(registry: registry)
    static let fact = SessionToolFact(text: "2 files", accessory: .diff(added: 12, removed: 3))
    static let changes = SessionToolContribution(
        spec: SessionToolSpec(id: .changes, places: [.side, .fact, .off], defaultPlace: .side),
        title: "Changes", systemImage: "plus.forwardslash.minus", fact: { _ in fact },
        pane: { _ in AnyView(GitChangesInspector(model: GitPreviewFixtures.model)) })

    static var context: SessionToolContext? {
        session.map { SessionToolContext(session: $0, screen: screen, tool: .changes) }
    }

    static func title(hasChanges: Bool = true) -> some View {
        SessionToolsTitle(
            title: "Review the session tools changes", location: "feature/session-tools-with-a-long-branch-name",
            facts: hasChanges ? [(changes, fact)] : [], isOpen: { _ in false }, action: { _ in })
    }

    @ViewBuilder static var sidePanel: some View {
        if let context {
            SessionToolsSidePanel(
                tabs: [changes], open: changes, context: { _ in context }, select: { _ in }, close: {}
            )
            .frame(width: DS.SessionTools.sidePanelIdealWidth, height: 500)
        }
    }

    static func stateTool(_ state: String) -> SessionToolContribution {
        var tool = changes
        tool.pane = { _ in
            switch state {
            case "Loading":
                AnyView(LoadingStateView("Reading changes"))
            case "Error":
                AnyView(
                    EmptyStateView(
                        "Couldn't read the repository", systemImage: "exclamationmark.triangle",
                        message: "Reconnect to the task's host, then try again."
                    ) {
                        Button("Try Again") {}
                    })
            default:
                AnyView(GitChangesInspector(model: GitPreviewFixtures.cleanModel))
            }
        }
        return tool
    }
}
#endif
