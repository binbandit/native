import SessionTools
import SwiftUI

/// Open In as a session tool: the default editor's name and icon under the title, which opens the
/// task's folder there (⇧⌘O too). Its menu lists every app that can open it, and Copy Path.
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
            perform: { openIn.openInDefaultApp(location($0)) },
            menu: { AnyView(OpenInMenuContent(location: location($0), model: openIn)) })
    }
}
