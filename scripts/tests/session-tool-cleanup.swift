import Foundation
import SessionTools
import SwiftUI

@testable import Native

@main
@MainActor
private struct SessionToolCleanupRegression {
    static func main() {
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
        print("Tool removal, original context, reset, pending-open cancellation and close-once checks passed")
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
