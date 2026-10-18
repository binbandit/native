import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#endif

/// Files or an image arriving to be attached: from ⌘V (files copied in the Finder, or an image
/// with no text alongside, such as a screenshot) or from a picker.
enum IncomingAttachments: Equatable {
    case files([URL])
    case image(Data, UTType)
}

extension View {
    /// While `isEnabled`, hands ⌘V of files or an image to `perform`, ahead of the focused text view,
    /// which would paste a file's name or nothing. Text pastes as usual. Mac only: iPadOS pastes
    /// images through its own edit menu.
    func onAttachmentPaste(isEnabled: Bool, perform: @escaping (IncomingAttachments) -> Void) -> some View {
        #if canImport(AppKit)
        background(AttachmentPasteMonitor(isEnabled: isEnabled, perform: perform))
        #else
        self
        #endif
    }
}

#if canImport(AppKit)
/// Watches this window's key events for ⌘V while enabled.
private struct AttachmentPasteMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let perform: (IncomingAttachments) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.perform = perform
        context.coordinator.update(isEnabled: isEnabled, in: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.update(isEnabled: false, in: view)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(perform: perform)
    }

    final class Coordinator {
        var perform: (IncomingAttachments) -> Void
        private var monitor: Any?

        init(perform: @escaping (IncomingAttachments) -> Void) {
            self.perform = perform
        }

        func update(isEnabled: Bool, in view: NSView) {
            if isEnabled, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                    guard let self, let view, Self.isPaste(event), event.window == nil || event.window === view.window,
                        let pasted = Self.attachments(on: Self.pasteboard)
                    else { return event }
                    perform(pasted)
                    return nil
                }
            } else if !isEnabled, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private static func isPaste(_ event: NSEvent) -> Bool {
            event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
                && event.charactersIgnoringModifiers == "v"
        }

        /// The general pasteboard; a development build can read a named one instead
        /// (`-debugAttachmentPasteboard <name>`), so a test never touches the user's clipboard.
        private static var pasteboard: NSPasteboard {
            #if DEBUG
            if let name = UserDefaults.standard.string(forKey: "debugAttachmentPasteboard") {
                return NSPasteboard(name: NSPasteboard.Name(name))
            }
            #endif
            return .general
        }

        static func attachments(on pasteboard: NSPasteboard) -> IncomingAttachments? {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
                return .files(urls)
            }
            // Copied text that happens to carry a picture pastes as text.
            guard pasteboard.string(forType: .string) == nil else { return nil }
            let images: [(NSPasteboard.PasteboardType, UTType)] = [
                (.png, .png), (NSPasteboard.PasteboardType(UTType.jpeg.identifier), .jpeg), (.tiff, .tiff),
            ]
            for (type, contentType) in images {
                if let data = pasteboard.data(forType: type) {
                    return .image(data, contentType)
                }
            }
            return nil
        }
    }
}
#endif
