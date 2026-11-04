import ACP
import Foundation
import SessionTools
import SwiftUI

@testable import Native

@main
@MainActor
private struct SessionToolCleanupRegression {
    static func main() throws {
        let app = AppModel.preview(.empty)
        guard let session = SessionModel.preview(in: app) else { exit(1) }
        for place in [SessionToolPlace.side, .fact] {
            let registry = SessionToolRegistry(defaults: PreviewUserDefaults())
            let screen = SessionToolsScreenModel(registry: registry, session: session)
            let id: SessionToolID = "fixture.cleanup"
            let state = screen.state(for: id, CleanupState.init)
            var closed = 0
            let tool = SessionToolContribution(
                spec: SessionToolSpec(id: id, places: [place, .off], defaultPlace: place),
                title: "Fixture", systemImage: "wrench", pane: { _ in AnyView(EmptyView()) },
                didClose: { context in
                    require(context.session === session && context.screen === screen, "original session context")
                    closed += 1
                    context.state(CleanupState.init).value = "reset"
                })
            registry.setPluginTools([tool])
            screen.open(id)
            require(screen.isOpen(id), "fixture pane opened")
            registry.setPluginTools([])
            screen.closeRemovedTools()
            require(closed == 1 && state.value == "reset", "revocation resets retained state exactly once")
            screen.closeRemovedTools()
            screen.close(id)
            require(closed == 1, "repeated removal does not repeat cleanup")
            registry.setPluginTools([tool])
            require(screen.openTools.isEmpty, "re-enabling does not reopen a revoked pane")

            screen.open(id)
            registry.setPluginTools([
                SessionToolContribution(
                    spec: tool.spec, title: "Replacement", systemImage: "wrench",
                    pane: { _ in AnyView(EmptyView()) },
                    didClose: { _ in
                        require(false, "an existing pane must retain its original close hook")
                    })
            ])
            screen.close(place)
            screen.close(place)
            require(closed == 2, "ordinary close keeps the original hook and runs it once")

            registry.setPluginTools([tool])
            if place == .side {
                var pending: (@MainActor () -> Void)?
                screen.makeRoomForSidePanel = { pending = $0 }
                screen.open(id)
                require(pending != nil && screen.openTools.isEmpty, "open waits for room")
                registry.setPluginTools([])
                screen.closeRemovedTools()
                pending?()
                registry.setPluginTools([tool])
                pending?()
                screen.close(id)
                require(closed == 2 && screen.openTools.isEmpty, "cancelled pending opens stay closed without cleanup")
                screen.makeRoomForSidePanel = { $0() }
            }

            let otherID: SessionToolID = "fixture.other"
            var otherClosed = 0
            let other = SessionToolContribution(
                spec: SessionToolSpec(id: otherID, places: [place], defaultPlace: place),
                title: "Other", systemImage: "wrench", pane: { _ in AnyView(EmptyView()) },
                didClose: { _ in otherClosed += 1 })
            registry.setPluginTools([tool, other])
            screen.open(id)
            screen.open(otherID)
            require(closed == 3 && otherClosed == 0, "replacement closes only the displaced pane")
            screen.close(place)
            require(otherClosed == 1, "replacement pane closes once")
            registry.setPluginTools([])
        }
        try checkRequestNavigation(app)
        checkContinuationSessions(app)
        print("Tool removal, request navigation, original context, continuation, reset and close-once checks passed")
    }

    private static func checkRequestNavigation(_ app: AppModel) throws {
        for approval in [false, true] {
            guard let session = SessionModel.preview(in: app, agent: "claude-code") else { exit(1) }
            let registry = SessionToolRegistry(defaults: PreviewUserDefaults())
            let screen = SessionToolsScreenModel(registry: registry, session: session)
            let changes = SessionToolContribution(
                spec: SessionToolSpec(id: .changes, places: [.side], defaultPlace: .side),
                title: "Changes", systemImage: "doc", pane: { _ in AnyView(EmptyView()) })
            registry.setPluginTools([changes])
            if approval {
                session.previewPermissionRequest(command: "swift test", reason: "Run focused tests")
                session.mirrorState()
            } else {
                let request = try JSONDecoder().decode(
                    CreateElicitationRequest.self,
                    from: Data(
                        """
                        {"sessionId":"request-navigation","mode":"form","message":"Which layout?",
                         "requestedSchema":{"type":"object","properties":{"layout":{"type":"string"}}}}
                        """.utf8))
                session.requestQuestion(request, id: .int(1))
            }
            require(session.taskWellAsk?.session === session, "request belongs to the primary transcript")
            screen.open(.changes)
            func layout() -> SessionToolPanelLayout {
                SessionToolPanelLayout(
                    open: screen.openByPlace, availableWidth: 500,
                    minimumConversationWidth: DS.SessionTools.conversationBesidePanelMinWidth,
                    panelWidth: DS.SessionTools.sidePanelIdealWidth, replacingConversationWith: .changes)
            }
            require(layout().replacement == .changes, "narrow Changes pane hides the transcript")
            require(screen.focusTaskAttention(in: session) == nil, "parent request stays in the primary transcript")
            require(layout().replacement == nil, "Show the request reveals the transcript")
            require(session.wantsComposerFocus, "the revealed request receives the focus request")
            app.sessions.remove(session)
        }
    }

    private static func checkContinuationSessions(_ app: AppModel) {
        for sameKey in [false, true] {
            for alreadyOpen in [false, true] {
                var original = SessionModel.preview(in: app)
                guard let originalKey = original?.key, let originalID = original.map({ ObjectIdentifier($0) }) else {
                    exit(1)
                }
                weak let retired: SessionModel? = original
                let registry = SessionToolRegistry(defaults: PreviewUserDefaults())
                let screen = SessionToolsScreenModel(registry: registry, session: original)
                let id: SessionToolID = "fixture.continuation"
                var closed: [ObjectIdentifier] = []
                let tool = SessionToolContribution(
                    spec: SessionToolSpec(id: id, places: [.fact], defaultPlace: .fact),
                    title: "Continuation", systemImage: "wrench", pane: { _ in AnyView(EmptyView()) },
                    didClose: { closed.append(ObjectIdentifier($0.session)) })
                registry.setPluginTools([tool])
                if alreadyOpen { screen.open(id) }
                if let original { app.sessions.remove(original) }
                guard
                    let replacement = SessionModel.preview(
                        in: app, id: sameKey ? originalKey.id.rawValue : UUID().uuidString)
                else { exit(1) }
                replacement.continuedTaskKey = originalKey
                require(replacement.taskPresentationKey == originalKey, "continuation retains view identity")
                screen.bind(to: replacement)
                original = nil
                if alreadyOpen {
                    require(retired != nil, "an existing pane retains its original cleanup context")
                    screen.close(id)
                    require(closed == [originalID], "an existing pane closes with its original session")
                }
                require(retired == nil, "the previous session releases after its panes close")
                screen.open(id)
                registry.setPluginTools([])
                screen.closeRemovedTools()
                screen.close(id)
                let expected = (alreadyOpen ? [originalID] : []) + [ObjectIdentifier(replacement)]
                require(closed == expected, "new panes close once with the replacement session")
                app.sessions.remove(replacement)
            }
        }
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            print("FAIL: \(message)")
            exit(1)
        }
    }
}

@MainActor
private final class CleanupState {
    var value = "retained"
}
