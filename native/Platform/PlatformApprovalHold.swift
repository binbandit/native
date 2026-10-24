import SwiftUI

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

enum PlatformApprovalHold {
    static var usesConfirmation: Bool {
        #if canImport(AppKit)
        NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
        #else
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
        #endif
    }

    static func acknowledge() {
        #if canImport(AppKit)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #else
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

extension View {
    func approvalHoldKeys(enabled: Bool, changed: @escaping (Bool) -> Void) -> some View {
        #if canImport(AppKit)
        background(ApprovalHoldKeyMonitor(enabled: enabled, changed: changed))
        #else
        modifier(ApprovalHoldKeyRegistration(enabled: enabled, changed: changed))
        #endif
    }
}

#if canImport(AppKit)
private struct ApprovalHoldKeyMonitor: NSViewRepresentable {
    let enabled: Bool
    let changed: (Bool) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.changed = changed
        context.coordinator.update(view: view, enabled: enabled)
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator {
        var changed: ((Bool) -> Void)?
        private var monitor: Any?
        private var observer: (any NSObjectProtocol)?
        private var heldKeyCode: UInt16?

        func update(view: NSView, enabled: Bool) {
            guard enabled else { stop(); return }
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) {
                [weak self, weak view] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, let view else { return false }
                    return self.handle(event, in: view)
                }
                return consumed ? nil : event
            }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
            ) { [weak self] _ in
                // Any focus transfer between this app's windows cancels a held shortcut.
                MainActor.assumeIsolated { self?.release() }
            }
        }

        private func handle(_ event: NSEvent, in view: NSView) -> Bool {
            guard let window = view.window, event.window === window else { return false }
            let commandOnly = event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
            if event.type == .flagsChanged, !commandOnly {
                release()
                return false
            }
            if event.type == .keyUp, event.keyCode == heldKeyCode {
                release()
                return true
            }
            guard event.type == .keyDown, commandOnly,
                event.charactersIgnoringModifiers?.lowercased() == "y"
            else { return false }
            if heldKeyCode == nil { heldKeyCode = event.keyCode; changed?(true) }
            return true
        }

        private func release() {
            if heldKeyCode != nil { heldKeyCode = nil; changed?(false) }
        }
        func stop() {
            release()
            if let monitor { NSEvent.removeMonitor(monitor) }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            monitor = nil
            observer = nil
        }
    }
}
#endif
