import SwiftUI
import UniformTypeIdentifiers

/// Ordinary text still inserts at the caret. File and image representations must reach the
/// surrounding attachment destination, even when the same item also offers plain text.
struct ComposerTextDrop: DropDelegate {
    let insert: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !info.hasItemsConforming(to: [.url, .image]) && info.hasItemsConforming(to: [.text])
            && !info.itemProviders(for: [.item]).contains {
                !$0.registeredTypeIdentifiers(fileOptions: .openInPlace).isEmpty
            }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        let providers = info.itemProviders(for: [.text])
        Task {
            var parts: [String] = []
            for provider in providers {
                let text: String? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                        continuation.resume(returning: object as? String)
                    }
                }
                if let text { parts.append(text) }
            }
            if !parts.isEmpty { insert(parts.joined(separator: "\n")) }
        }
        return !providers.isEmpty
    }
}
