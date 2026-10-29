#if canImport(UIKit)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// File paste uses UIKit's edit menu too, including a hardware keyboard's Command-V.
struct PlatformAttachmentPasteIOS: UIViewRepresentable {
    let isEnabled: Bool
    let perform: (IncomingAttachments) -> Void

    func makeUIView(context: Context) -> UIView { UIView() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.perform = perform
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak view] in
            guard let view, coordinator.isMounted else { return }
            coordinator.update(in: view, enabled: isEnabled)
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.isMounted = false
        coordinator.restore()
    }

    final class Coordinator: NSObject, UITextPasteDelegate {
        var perform: ((IncomingAttachments) -> Void)?
        var isMounted = true
        private weak var editor: UITextView?
        // NSObject's capability queries are nonisolated. UIKit installs and invokes this delegate
        // on the main actor; these overrides only forward its optional method availability.
        nonisolated(unsafe) private weak var previousDelegate: (any UITextPasteDelegate)?
        private var previousConfiguration: UIPasteConfiguration?

        func update(in anchor: UIView, enabled: Bool) {
            guard enabled else { restore(); return }
            var ancestor = anchor.superview
            for _ in 0..<4 {
                guard let view = ancestor else { return }
                if let text = Self.editor(in: view, depth: 6) {
                    if editor !== text {
                        restore()
                        editor = text
                    }
                    if text.pasteDelegate !== self {
                        previousDelegate = text.pasteDelegate
                        previousConfiguration = text.pasteConfiguration
                        text.pasteDelegate = self
                        let configuration = UIPasteConfiguration(forAccepting: NSString.self)
                        configuration.addAcceptableTypeIdentifiers([UTType.item.identifier])
                        text.pasteConfiguration = configuration
                    }
                    return
                }
                ancestor = view.superview
            }
        }

        func restore() {
            if let editor, editor.pasteDelegate === self {
                editor.pasteDelegate = previousDelegate
                editor.pasteConfiguration = previousConfiguration
            }
            editor = nil
        }

        nonisolated override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
        }

        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            previousDelegate?.responds(to: selector) == true ? previousDelegate : super.forwardingTarget(for: selector)
        }

        func textPasteConfigurationSupporting(
            _ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
            transform item: any UITextPasteItem
        ) {
            let provider = item.itemProvider
            guard ComposerDropItem.acceptsPaste(provider) else {
                if let previousDelegate,
                    previousDelegate.responds(to: #selector(Self.textPasteConfigurationSupporting(_:transform:)))
                {
                    previousDelegate.textPasteConfigurationSupporting?(
                        textPasteConfigurationSupporting, transform: item)
                } else {
                    item.setDefaultResult()
                }
                return
            }
            item.setNoResult()
            let accept = perform
            Task {
                do {
                    switch try await ComposerDropItem.load(provider) {
                    case .file(let url): accept?(.files([url]))
                    case .image(let data, let type): accept?(.image(data, type))
                    case .failed(let name): accept?(.failed(name))
                    }
                } catch {
                    accept?(.failed(provider.suggestedName ?? "file"))
                }
            }
        }

        private static func editor(in view: UIView, depth: Int) -> UITextView? {
            if let text = view as? UITextView { return text }
            guard depth > 0 else { return nil }
            return view.subviews.lazy.compactMap { editor(in: $0, depth: depth - 1) }.first
        }
    }
}
#endif
