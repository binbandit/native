import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

/// A directory-only system picker. The Mac panel attaches to this view's own window and never
/// changes the active application. Files supplies security-scoped directory URLs on iPad.
struct PlatformFolderPicker: ViewModifier {
    @Binding var isPresented: Bool
    let enabled: Bool
    let directory: URL?
    let completion: (Result<URL?, any Error>) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        if enabled {
            content.background {
                FolderPanelAnchor(isPresented: $isPresented, directory: directory, completion: completion)
                    .frame(width: 0, height: 0)
            }
        } else {
            content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder]) { result in
                completion(result.map { Optional($0) })
            }
        }
        #else
        content.fileImporter(isPresented: $isPresented, allowedContentTypes: [.folder]) { result in
            completion(result.map { Optional($0) })
        }
        #endif
    }
}

#if os(macOS)
private struct FolderPanelAnchor: NSViewRepresentable {
    @Binding var isPresented: Bool
    let directory: URL?
    let completion: (Result<URL?, any Error>) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ view: NSView, context: Context) {
        guard isPresented, context.coordinator.panel == nil, let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        context.coordinator.panel = panel
        let responder = window.firstResponder
        panel.beginSheetModal(for: window) { response in
            context.coordinator.panel = nil
            isPresented = false
            if let responder { window.makeFirstResponder(responder) }
            completion(.success(response == .OK ? panel.url : nil))
        }
    }

    final class Coordinator {
        var panel: NSOpenPanel?
    }
}
#endif
