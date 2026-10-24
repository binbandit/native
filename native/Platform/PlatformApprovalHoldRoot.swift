import SwiftUI

extension View {
    func approvalHoldKeyRoot() -> some View {
        #if canImport(AppKit)
        self
        #else
        modifier(ApprovalHoldKeyRoot())
        #endif
    }
}

#if !canImport(AppKit)
import UIKit

/// A window owns its route. The approval registers interest without taking the editor's focus.
private final class ApprovalHoldKeyRoute {
    private var owner: UUID?
    private var changed: ((Bool) -> Void)?
    private var held = false

    func register(_ owner: UUID, changed: @escaping (Bool) -> Void) {
        cancel()
        self.owner = owner
        self.changed = changed
    }

    func remove(_ owner: UUID) {
        guard self.owner == owner else { return }
        cancel()
        self.owner = nil
        changed = nil
    }

    func cancel() {
        if held { held = false; changed?(false) }
    }

    func handle(_ press: KeyPress) -> KeyPress.Result {
        guard changed != nil else { return .ignored }
        guard press.key == "y", press.modifiers == .command else {
            cancel()
            return .ignored
        }
        if press.phase == .up {
            cancel()
        } else if !held {
            held = true
            changed?(true)
        }
        return .handled
    }
}

private extension EnvironmentValues {
    @Entry var approvalHoldKeyRoute: ApprovalHoldKeyRoute?
}

private struct ApprovalHoldKeyRoot: ViewModifier {
    @State private var route = ApprovalHoldKeyRoute()
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .environment(\.approvalHoldKeyRoute, route)
            // The root is an ancestor of the sidebar, toolbar and transcript, so a card does
            // not have to receive focus before its approval can receive a held shortcut.
            .onKeyPress(phases: [.down, .repeat, .up]) { route.handle($0) }
            .onChange(of: scenePhase) { _, phase in if phase != .active { route.cancel() } }
            .onReceive(NotificationCenter.default.publisher(for: UIWindow.didResignKeyNotification)) { _ in
                route.cancel()
            }
            .onDisappear { route.cancel() }
    }
}

struct ApprovalHoldKeyRegistration: ViewModifier {
    let enabled: Bool
    let changed: (Bool) -> Void
    @Environment(\.approvalHoldKeyRoute) private var route
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onChange(of: enabled, initial: true) { _, enabled in
                if enabled { route?.register(owner, changed: changed) } else { route?.remove(owner) }
            }
            .onDisappear { route?.remove(owner) }
    }
}
#endif
