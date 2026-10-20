import SessionTools
import SwiftUI

/// Open In as a session tool: the default editor's name and icon under the title, which opens the
/// task's folder there. The others are in the menu bar's Open In (⇧⌘O opens the default).
@MainActor
enum SessionOpenInTool {
    static func contribution(model: AppModel, openIn: OpenInModel = .shared) -> SessionToolContribution {
        let location = { (context: SessionToolContext) in
            OpenInLocation(folder: context.session.cwd, host: model.currentProject?.host ?? .local)
        }
        return SessionToolContribution(
            spec: SessionToolSpec(id: .openIn, places: [.fact, .off], defaultPlace: .fact),
            title: "Open In", systemImage: "arrow.up.forward.app",
            fact: { context in
                openIn.defaultApp(for: location(context)).map {
                    SessionToolFact(text: $0.name, accessory: .icon(openIn.icon(for: $0)))
                }
            },
            perform: { openIn.openInDefaultApp(location($0)) })
    }
}
