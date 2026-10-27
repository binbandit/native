import ACP
import SwiftUI
import UniformTypeIdentifiers

struct NoProjectMoveSheet: View {
    let task: SessionKey
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var folder: URL?
    @State private var copyFiles = false
    @State private var isChoosingFolder = false
    @State private var isMoving = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            Text("Move to Project").font(.dsTitle3).foregroundStyle(.dsTextPrimary)
            Text("Continue this conversation in a project folder.")
                .font(.dsBody).foregroundStyle(.dsTextSecondary)
            HStack(spacing: DS.Space.md) {
                Image(systemName: "folder").foregroundStyle(.dsTextSecondary)
                Text(folder?.lastPathComponent ?? "Choose a project folder")
                    .font(.dsBody).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: DS.Space.sm)
                Menu("Choose Folder…") {
                    ForEach(model.projects.all) { project in
                        Button(project.name) { folder = project.url }
                    }
                    Divider()
                    Button("Other Folder…") { isChoosingFolder = true }
                }
                .menuStyle(.automatic).fixedSize()
                .accessibilityLabel("Choose project folder")
            }
            SeparatorLine()
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Toggle("Copy task files into the project", isOn: $copyFiles)
                    .toggleStyle(.automatic)
                    .font(.dsBody)
                Text(
                    "Copies into a new Task Files subfolder. Existing files stay untouched. Private originals stay with this task until deletion."
                )
                .font(.dsCaption).foregroundStyle(.dsTextTertiary)
                .padding(.leading, DS.Space.xxl)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let failure {
                Text(failure).font(.dsBody).foregroundStyle(.dsAttention)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("moveToProject.failure")
            }
            HStack(spacing: DS.Space.sm) {
                if isMoving {
                    DotGridLoader(pattern: .settingUp)
                        .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                    Text("Moving…").font(.dsBody).foregroundStyle(.dsTextSecondary)
                }
                Spacer(minLength: DS.Space.md)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    .buttonStyle(.ds(.secondary, size: .medium)).disabled(isMoving)
                Button("Move", action: move).keyboardShortcut(.defaultAction)
                    .buttonStyle(.ds(.primary, size: .medium)).disabled(folder == nil || isMoving)
                    .accessibilityIdentifier("moveToProject.move")
            }
        }
        .padding(DS.Space.xxl)
        .frame(
            minWidth: DS.isTouchPlatform ? nil : DS.TaskWorkspace.sheetWidth,
            idealWidth: DS.TaskWorkspace.sheetWidth, maxWidth: DS.TaskWorkspace.sheetWidth
        )
        .background(.dsBackground)
        .disabled(isMoving)
        .interactiveDismissDisabled(isMoving)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let chosen): folder = chosen
            case .failure(let error): failure = error.localizedDescription
            }
        }
    }

    private func move() {
        guard let folder, !isMoving else { return }
        isMoving = true
        failure = nil
        Task {
            do {
                try await model.moveToProject(task, folder: folder, copyFiles: copyFiles)
                dismiss()
            } catch {
                failure = "Couldn't move the task. \(error.localizedDescription) Your private files are kept."
                isMoving = false
            }
        }
    }
}

extension View {
    func noProjectMovePresentation() -> some View { modifier(NoProjectMovePresentation()) }
}

private struct NoProjectMovePresentation: ViewModifier {
    @Environment(AppModel.self) private var model
    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(
                get: { model.movingProjectlessTask != nil },
                set: { if !$0 { model.movingProjectlessTask = nil } }
            )
        ) {
            if let key = model.movingProjectlessTask { NoProjectMoveSheet(task: key) }
        }
    }
}

#if DEBUG
#Preview("Move to Project - Choose a folder") {
    DSPreviewPair {
        NoProjectMoveSheet(
            task: SessionKey(agent: AgentDefinition.ID(rawValue: "claude-code"), id: SessionID("preview"))
        )
        .environment(AppModel.preview(.empty))
    }
}
#endif

#if DEBUG
extension NoProjectMoveSheet {
    fileprivate static func preview(moving: Bool = false, failure: String? = nil) -> Self {
        var view = Self(task: SessionKey(agent: AgentDefinition.ID(rawValue: "claude-code"), id: SessionID("preview")))
        view._folder = State(initialValue: URL(filePath: "/Development/atlas"))
        view._isMoving = State(initialValue: moving)
        view._failure = State(initialValue: failure)
        return view
    }
}

#Preview("Move to Project - Ready, moving and failed") {
    let app = AppModel.preview(.empty)
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            NoProjectMoveSheet.preview()
            NoProjectMoveSheet.preview(moving: true)
            NoProjectMoveSheet.preview(failure: "Couldn't reopen the task in this folder. Your private files are kept.")
        }
        .environment(app)
    }
}
#endif
