#if canImport(Skills)
import Skills
import SwiftUI

/// Updating a skill Native installed: fetch it again from where it came from, show what changes,
/// and replace every copy once the user confirms. The old version goes to Native's trash.
struct SkillUpdateSheet: View {
    let library: SkillLibrary
    let item: SkillItem
    let onUpdated: ([SkillTrashEntry]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var plan: SkillUpdatePlan?
    @State private var error: String?
    @State private var isWorking = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("Update \(item.name)")
                    .settingsText(.title)
                    .foregroundStyle(.dsTextPrimary)
                if let record = library.record(for: item) {
                    Text("From \(record.source.displayText)")
                        .font(SettingsTextStyle.mono.font)
                        .foregroundStyle(.dsTextTertiary)
                        .textSelection(.enabled)
                }
            }
            if let error {
                Text(error)
                    .settingsText(.body)
                    .foregroundStyle(.dsDanger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let plan {
                changes(plan)
            } else {
                HStack(spacing: DS.Space.md) {
                    DotGridLoader(pattern: .settingUp)
                    Text("Fetching the latest version…")
                        .settingsText(.body)
                        .foregroundStyle(.dsTextSecondary)
                }
            }
            HStack(spacing: DS.Space.md) {
                Spacer()
                Button("Cancel") {
                    if let plan { library.discard(plan.stage) }
                    dismiss()
                }
                .buttonStyle(.ds(.secondary, size: .large))
                .keyboardShortcut(.cancelAction)
                if error != nil {
                    Button("Try Again") { Task { await fetch() } }
                        .buttonStyle(.ds(.primary, size: .large))
                } else {
                    Button("Update") { Task { await update() } }
                        .buttonStyle(.ds(.primary, size: .large))
                        .keyboardShortcut(.defaultAction)
                        .disabled(isWorking || plan?.changes.isEmpty != false)
                }
            }
        }
        .padding(DS.Space.xxl)
        .frame(width: 600)
        .background(.dsBackground)
        .task { await fetch() }
    }

    private func changes(_ plan: SkillUpdatePlan) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if plan.changes.isEmpty {
                Text("It's up to date: nothing changed since it was installed.")
                    .settingsText(.body)
                    .foregroundStyle(.dsTextSecondary)
            } else {
                Text("What changes")
                    .settingsText(.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                ForEach(plan.changes.added, id: \.self) { line("Added", $0) }
                ForEach(plan.changes.changed, id: \.self) { line("Changed", $0) }
                ForEach(plan.changes.removed, id: \.self) { line("Removed", $0) }
                if !plan.skill.scripts.isEmpty {
                    Text("It includes scripts an agent can run. Read the new version's files before updating.")
                        .settingsText(.caption)
                        .foregroundStyle(.dsWarning)
                    SkillFileList(files: plan.skill.scripts)
                }
                Text(
                    "Replaces \(plan.record.paths.map { SkillPaths.abbreviated($0, home: library.home) }.joined(separator: ", "))."
                )
                .settingsText(.caption)
                .foregroundStyle(.dsTextTertiary)
            }
        }
    }

    private func line(_ kind: String, _ path: String) -> some View {
        HStack(spacing: DS.Space.md) {
            Badge(kind, tone: kind == "Removed" ? .danger : kind == "Added" ? .success : .neutral)
            Text(path)
                .font(SettingsTextStyle.mono.font)
                .foregroundStyle(.dsTextPrimary)
        }
    }

    private func fetch() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            plan = try await library.stageUpdate(of: item)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func update() async {
        guard let plan else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            onUpdated(try await library.applyUpdate(plan))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
