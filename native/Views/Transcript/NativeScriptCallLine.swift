import ACP
import SwiftUI

/// A call a script made through Native's run_script (`MCPScriptRun`), shown as a quiet line under
/// the run_script row so nothing a script does is invisible: "rea · list_functions". While it waits
/// for approval it's a full row with the card instead.
struct NativeScriptCallLine: View {
    let call: ToolCallState

    /// Whether `call` is one Native made for a script, by its `_meta.native.script`.
    static func isScriptCall(_ call: ToolCallState) -> Bool {
        call.meta?["native"]?["script"] != nil
    }

    var body: some View {
        let phase = ToolPhase(call)
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "arrow.turn.down.right")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .accessibilityHidden(true)
            Text(label)
                .font(.dsCaption)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
            switch phase {
            case .failed: Text("failed").font(.dsCaption).foregroundStyle(.dsDanger)
            case .cancelled: Text("cancelled").font(.dsCaption).foregroundStyle(.dsTextTertiary)
            case .running: Text("running").font(.dsCaption).foregroundStyle(.dsTextTertiary)
            case .completed, .awaitingApproval: EmptyView()
            }
        }
        .padding(.leading, DS.Space.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Script called \(label)")
    }

    private var label: String {
        call.title.isEmpty ? call.name ?? "a tool" : call.title
    }
}
