import SwiftUI

/// Edits the setup script a project's new worktrees run, as a sheet.
struct GitSetupScriptEditor: View {
    let settings: GitSettings
    /// The project's main checkout.
    let root: URL
    @Environment(\.dismiss) private var dismiss
    @State private var script = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text("Setup Script for \(root.lastPathComponent)")
                .font(.dsHeadline)
                .foregroundStyle(.dsTextPrimary)
            Text(
                "Runs with your shell in each new worktree, after env files are copied. NATIVE_WORKSPACE_PATH, NATIVE_ROOT_PATH and NATIVE_BRANCH are set."
            )
            .font(.dsBody)
            .foregroundStyle(.dsTextSecondary)
            TextEditor(text: $script)
                .font(.dsMono)
                .scrollContentBackground(.hidden)
                .padding(DS.Space.sm)
                .frame(minHeight: GitMetrics.scriptEditorHeight)
                .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).strokeBorder(
                        .dsBorder, lineWidth: 1)
                }
                .accessibilityLabel("Setup script")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.ds(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    settings.setSetupScript(script, forProjectAt: root)
                    dismiss()
                }
                .buttonStyle(.ds(.primary))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: GitMetrics.commitWidth + DS.Space.xxxl * 3)
        .onAppear { script = settings.setupScript(forProjectAt: root) ?? "" }
    }
}
