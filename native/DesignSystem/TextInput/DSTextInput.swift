import SwiftUI

#if !NATIVE_PREVIEWS_WIP
import TextInput
#endif

/// Native multiline editing. Bind the document, not its display string: file tokens expand only
/// in `document.plainText`, which is the text to send to an agent. Selection uses UTF-16 editor offsets.
struct DSTextInput: View {
    @Binding var document: TextInputDocument
    var placeholder = "What would you like to work on?"
    var maximumLines = 10
    var fontSize = DS.TextInput.fontSize
    var lineSpacing = DS.TextInput.lineSpacing
    var accessibilityLabel = "Message"
    /// Optional control of focus and selection, including completion insertion in the middle.
    var isFocused: Binding<Bool>?
    var selection: Binding<NSRange>?
    var onSubmit: () -> Void = {}
    /// Return true to consume the key. Return is offered here before submission.
    var onKey: (DSTextInputKey) -> Bool = { _ in false }
    /// Modified keys are offered before native editing, for host actions such as steering.
    var onEvent: (DSTextInputEvent) -> Bool = { _ in false }
    var onAttachments: ([DSTextInputAttachment]) -> Void = { _ in }
    /// Caret rectangle in this component's coordinate space, after scrolling. Anchor above minY.
    var onStateChange: (DSTextInputState) -> Void = { _ in }
    /// Delivered after layout, deduplicated. Do not use this to set this view's own height.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        PlatformDSTextInput(input: self)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct DSTextInputState: Equatable {
    let selection: NSRange
    let caret: CGRect
    let query: TextInputQuery?
    let isComposing: Bool
}

enum DSTextInputKey: Equatable {
    case submit, up, down, escape, tab
}

struct DSTextInputEvent {
    let key: KeyEquivalent
    var modifiers: EventModifiers = []
    var isRepeat = false
}

enum DSTextInputAttachment {
    case file(URL)
    case image(Data, contentType: String)
}

extension DS {
    nonisolated enum TextInput {
        static let fontSize: CGFloat = 13
        static let lineSpacing: CGFloat = 4
        static let inset: CGFloat = 8
        static let tokenInset: CGFloat = 4
        static let tokenRadius: CGFloat = 4
        static let tokenMaximumWidth: CGFloat = 220
        static let previewWidth: CGFloat = 360
        static let fixtureWidth: CGFloat = 500
    }
}
