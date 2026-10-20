import SwiftUI

/// What the keyboard does from here, as quiet caps and words: `/` for commands, `@` for files, and
/// the palette, plus the project's action ⇧⌘R runs again when there is one. Hints that don't fit
/// drop from the end, so a narrow window keeps the composer's own keys.
struct NewSessionKeyHints: View {
    let keys: NewSessionContext.Keys
    /// The action Run Last runs, named in its hint.
    var lastAction: String?

    var body: some View {
        let hints = hints
        ViewThatFits(in: .horizontal) {
            ForEach((1...hints.count).reversed(), id: \.self) { count in
                row(Array(hints.prefix(count)))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private struct Hint: Hashable {
        let key: String
        let label: String
    }

    private var hints: [Hint] {
        var hints = [Hint(key: "/", label: "Commands"), Hint(key: "@", label: "Mention a file")]
        if let runLast = keys.runLast, let lastAction {
            hints.append(Hint(key: runLast, label: "Run \(lastAction)"))
        }
        if let palette = keys.palette {
            hints.append(Hint(key: palette, label: "Everything else"))
        }
        return hints
    }

    private func row(_ hints: [Hint]) -> some View {
        HStack(spacing: DS.Space.xl) {
            ForEach(hints, id: \.self) { hint in
                HStack(spacing: DS.Space.sm) {
                    Kbd(hint.key)
                    Text(hint.label)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(1)
                }
                .fixedSize()
            }
        }
    }
}
