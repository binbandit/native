import SwiftUI

/// A new session before its first message, resting on the composer: the project's name and exactly
/// where the task works, then a short ruled list of real ways to begin (go back to a task, take up
/// a pull request, run an action, have the agent show you around) and the keys for writing your own.
/// Text lines up on the composer's text inset; rules and the rows' hover span the column.
struct NewSessionView: View {
    let context: NewSessionContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NewSessionHeader(context: context)
                .padding(.horizontal, DS.Composer.textInsets.leading)
                .padding(.bottom, DS.Space.xl)
            VStack(spacing: 0) {
                ForEach(NewSessionStartingPoint.points(for: context)) { point in
                    SeparatorLine()
                    NewSessionLedgerRow(point: point)
                }
                SeparatorLine()
            }
            NewSessionKeysLine()
                .padding(.horizontal, DS.Composer.textInsets.leading)
                .padding(.top, DS.Space.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Under the starting points: the composer is there for anything else, and what `/` and `@` do in
/// it. Just the sentence when the keys don't fit.
private struct NewSessionKeysLine: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.sm) {
                Text("Or write your own below.")
                key("/", "for commands")
                key("@", "to mention a file")
            }
            Text("Or write your own below.")
        }
        .font(.dsBody)
        .foregroundStyle(.dsTextTertiary)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Or write your own below. Type slash for commands, at to mention a file.")
    }

    private func key(_ key: String, _ label: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            Kbd(key)
            Text(label)
        }
        .padding(.leading, DS.Space.xs)
    }
}
