#if DEBUG && canImport(AppKit)
import AppKit

/// Delivers a fixture drag to this isolated Debug window's actual registered destination. It never
/// starts a system drag or uses the general pasteboard, so another app cannot receive the fixture.
final class PlatformAttachmentDropCheck {
    private weak var anchor: NSView?
    private var observer: NSObjectProtocol?
    private var hovering: (NSView, PlatformAttachmentDraggingInfo)?

    init(anchor: NSView) {
        self.anchor = anchor
        guard Bundle.main.bundleIdentifier?.contains(".dev.") == true,
            UserDefaults.standard.bool(forKey: "debugAttachmentDropChecks")
        else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("dev.native.debug.dropAttachment"), object: nil, queue: .main
        ) { [weak self] notification in
            guard notification.object as? String == String(ProcessInfo.processInfo.processIdentifier) else { return }
            MainActor.assumeIsolated { self?.receive(notification.userInfo ?? [:]) }
        }
    }

    private func receive(_ request: [AnyHashable: Any]) {
        guard let token = request["token"] as? String else { return }
        var result = "No drop destination"
        defer {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("dev.native.debug.dropAttachmentResult"), object: token,
                userInfo: ["result": result], deliverImmediately: true)
        }
        if let (view, info) = hovering {
            view.draggingExited(info)
            hovering = nil
        }
        guard request["phase"] as? String != "exit" else { result = "Exited"; return }
        guard let window = anchor?.window, let root = window.contentView,
            let name = request["pasteboard"] as? String
        else { return }
        let point: NSPoint
        if request["target"] as? String == "composer", let editor = Self.editor(in: root) {
            point = editor.convert(NSPoint(x: editor.bounds.midX, y: editor.visibleRect.midY), to: nil)
        } else {
            point = root.convert(NSPoint(x: root.bounds.midX, y: root.bounds.midY), to: nil)
        }
        let info = PlatformAttachmentDraggingInfo(window: window, point: point, pasteboard: name)
        var candidate = root.hitTest(root.convert(point, from: nil))
        while let view = candidate {
            if info.draggingPasteboard.availableType(from: view.registeredDraggedTypes) != nil {
                let operation = view.draggingEntered(info)
                if !operation.isEmpty {
                    result = "Hover: \(NSStringFromClass(type(of: view)))"
                    if request["phase"] as? String == "hover" {
                        hovering = (view, info)
                    } else if view.prepareForDragOperation(info), view.performDragOperation(info) {
                        view.concludeDragOperation(info)
                        view.draggingEnded(info)
                        result = "Dropped: \(NSStringFromClass(type(of: view)))"
                    } else {
                        view.draggingExited(info)
                        result = "Drop refused"
                    }
                    return
                }
                view.draggingExited(info)
            }
            candidate = view.superview
        }
    }

    private static func editor(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView, editor.isEditable { return editor }
        return view.subviews.lazy.compactMap(editor).first
    }

    isolated deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
#endif
