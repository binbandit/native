import SwiftUI
import UniformTypeIdentifiers

extension View {
    func composerAttachmentDrop(
        isEnabled: Bool = true, isTargeted: @escaping (Bool) -> Void,
        perform: @escaping ([ComposerDropItem]) -> Void
    ) -> some View {
        onDrop(
            of: [.item], delegate: ComposerAttachmentDrop(isEnabled: isEnabled, targeted: isTargeted, perform: perform))
    }
}

/// File representations can also synthesize files from ordinary text. Admit actual file, URL and
/// image providers first, so dragging a selection never turns it into an attachment.
struct ComposerAttachmentDrop: DropDelegate {
    let isEnabled: Bool
    let targeted: (Bool) -> Void
    let perform: ([ComposerDropItem]) -> Void

    static func accepts(_ provider: NSItemProvider) -> Bool {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.folder.identifier)
            || !provider.registeredTypeIdentifiers(fileOptions: .openInPlace).isEmpty
        {
            return true
        }
        return provider.hasItemConformingToTypeIdentifier(UTType.data.identifier)
            && !provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
    }

    func validateDrop(info: DropInfo) -> Bool {
        isEnabled && info.itemProviders(for: [.item]).contains(where: Self.accepts)
    }

    func dropEntered(info: DropInfo) { targeted(true) }
    func dropExited(info: DropInfo) { targeted(false) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: isEnabled ? .copy : .forbidden) }

    func performDrop(info: DropInfo) -> Bool {
        targeted(false)
        guard isEnabled else { return false }
        let providers = info.itemProviders(for: [.item]).filter(Self.accepts)
        guard !providers.isEmpty else { return false }
        Task {
            var items: [ComposerDropItem] = []
            for provider in providers {
                let result: Result<ComposerDropItem, any Error> = await withCheckedContinuation { continuation in
                    _ = provider.loadTransferable(type: ComposerDropItem.self) { continuation.resume(returning: $0) }
                }
                switch result {
                case .success(let item): items.append(item)
                case .failure: items.append(.failed(provider.suggestedName ?? "file"))
                }
            }
            perform(items)
        }
        return true
    }
}
