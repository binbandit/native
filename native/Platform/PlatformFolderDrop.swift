import SwiftUI
import UniformTypeIdentifiers

/// External file URLs use their own drop delegate. Native's private reorder type remains with rows.
struct PlatformFolderDrop: ViewModifier {
    let enabled: Bool
    let model: AppModel
    let undoManager: UndoManager?

    func body(content: Content) -> some View {
        content
            .onDrop(
                of: enabled ? [.fileURL] : [], delegate: FolderURLDropDelegate(model: model, undoManager: undoManager)
            )
            .overlay {
                if enabled, model.sidebarFolders.acceptsDrop {
                    SidebarFolderDropFeedback(names: model.sidebarFolders.hovered)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct FolderURLDropDelegate: DropDelegate {
    let model: AppModel
    let undoManager: UndoManager?

    func validateDrop(info: DropInfo) -> Bool {
        !info.hasItemsConforming(to: [SidebarDragState.contentType]) && info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        let request = model.beginFolderDrop()
        Task {
            let urls = await load(info.itemProviders(for: [.fileURL]))
            await model.previewFolderDrop(urls, request: request)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: model.sidebarFolders.acceptsDrop ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) { model.endFolderDrop() }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        model.endFolderDrop()
        guard !providers.isEmpty else { return false }
        Task {
            let urls = await load(providers)
            await model.openSidebarFolders(urls, undoManager: undoManager)
        }
        return true
    }

    private func load(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSURL.self) { item, _ in
                    continuation.resume(returning: item as? URL)
                }
            }
            if let url { urls.append(url) }
        }
        return urls
    }
}
