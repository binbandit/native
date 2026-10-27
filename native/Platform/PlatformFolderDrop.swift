import SwiftUI
import UniformTypeIdentifiers

/// External file URLs use their own drop delegate. Native's private reorder type remains with rows.
struct PlatformFolderDrop<Feedback: View>: ViewModifier {
    let enabled: Bool
    let excludedTypes: [UTType]
    let accepts: () -> Bool
    let begin: () -> UUID
    let preview: ([URL], UUID) async -> Void
    let end: () -> Void
    let open: ([URL]) async -> Void
    @ViewBuilder let feedback: () -> Feedback

    func body(content: Content) -> some View {
        content
            .onDrop(
                of: enabled ? [.fileURL] : [],
                delegate: FolderURLDropDelegate(
                    excludedTypes: excludedTypes, accepts: accepts, begin: begin, preview: preview, end: end, open: open
                )
            )
            .overlay {
                if enabled, accepts() { feedback().allowsHitTesting(false) }
            }
    }
}

private struct FolderURLDropDelegate: DropDelegate {
    let excludedTypes: [UTType]
    let accepts: () -> Bool
    let begin: () -> UUID
    let preview: ([URL], UUID) async -> Void
    let end: () -> Void
    let open: ([URL]) async -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !info.hasItemsConforming(to: excludedTypes) && info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        let request = begin()
        Task {
            let urls = await load(info.itemProviders(for: [.fileURL]))
            await preview(urls, request)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: accepts() ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) { end() }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        end()
        guard !providers.isEmpty else { return false }
        Task {
            let urls = await load(providers)
            await open(urls)
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
