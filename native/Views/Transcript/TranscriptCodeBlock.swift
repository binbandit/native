import SwiftUI

/// A block of code in the transcript, in a reply or a message the user sent: highlighted for its
/// language, scrolling sideways rather than wrapping, with a copy button that shows on hover (and
/// always on touch).
struct TranscriptCodeBlock: View {
    let code: String
    let language: String?

    @State private var isHovering = false

    /// The code as a block shows it, without the newline a fence leaves at its end.
    static func shownCode(_ code: String) -> String {
        code.hasSuffix("\n") ? String(code.dropLast()) : code
    }

    var body: some View {
        let code = Self.shownCode(code)
        #if DEBUG || NATIVE_PERF
        let _ = TranscriptPerfProbe.codeRendered(code, language: language)
        #endif
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.dsMicro)
                    .foregroundStyle(.dsTextSecondary)
                    // A label, not code to copy; selectable text costs a text view's layout.
                    .textSelection(.disabled)
            }
            ScrollView(.horizontal) {
                HighlightedCode(code, language: language)
                    .codeTextStyle()
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            TranscriptCodeCopyButton(code: code)
                .padding(DS.Space.sm)
                .opacity(isHovering || DS.isTouchPlatform ? 1 : 0)
        }
        .nestedSurface(.dsCodeBlockBackground, minimumRadius: DS.Radius.card)
        .trackHover($isHovering)
    }
}

private struct TranscriptCodeCopyButton: View {
    let code: String

    @State private var didCopy = false

    var body: some View {
        Button {
            DSPasteboard.copy(code)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
                .font(.dsCaption)
                .foregroundStyle(.dsTextSecondary)
                .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                .background(.dsCodeBlockBackground, in: .rect(cornerRadius: DS.Radius.control))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .dsHitTarget(DS.Size.controlXS)
        .help("Copy code")
        .accessibilityLabel("Copy code")
    }
}
