import NativePolicy
import SwiftUI

/// Progress, failures and Undo remain beside the action until explicitly dismissed or replaced.
struct SidebarFolderResult: View {
    @Environment(AppModel.self) private var model
    @State private var showsContact = false

    var body: some View {
        let state = model.sidebarFolders
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if !state.opening.isEmpty {
                HStack(spacing: DS.Space.md) {
                    DotGridLoader(pattern: .settingUp).frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                    Text("Opening \(state.opening.joined(separator: ", "))")
                }
                .accessibilityLabel("Opening \(state.opening.joined(separator: ", "))")
            }
            if let receipt = state.receipt, state.opening.isEmpty {
                Text(
                    receipt.projects.count == 1
                        ? "Added \(receipt.projects[0].name)." : "Added \(receipt.projects.count) folders.")
                HStack(spacing: DS.Space.lg) {
                    Button("Undo") { model.undoOfferedFolderAddition(receipt) }
                        .accessibilityLabel("Undo Add Folder")
                    if state.failures.isEmpty { dismiss }
                }
            }
            ForEach(Array(state.failures.enumerated()), id: \.offset) { _, failure in
                Text(failure.message).foregroundStyle(.dsDanger)
            }
            if !state.failures.isEmpty {
                HStack(spacing: DS.Space.lg) {
                    Button(
                        state.failures.contains { $0.needsLocation }
                            ? "Locate Folder…" : "Choose Folder…",
                        action: model.requestOpenFolder)
                    dismiss
                }
            }
            if model.folderPolicy.isManaged(.foldersAllowedRoots) {
                Text(
                    model.canOpenFolders
                        ? "Managed by \(model.folderPolicy.organizationName ?? "your organization").\nOnly approved folders can be added."
                        : "Adding folders is managed by \(model.folderPolicy.organizationName ?? "your organization")."
                )
                .overlay(alignment: .topLeading) {
                    Image(systemName: "lock").font(.dsCaption)
                        .offset(x: -(DS.Size.rowLeading + DS.Space.sm))
                }
                if let contact = model.folderPolicy.organizationContact {
                    Button("Request a Change…") { showsContact.toggle() }
                        .popover(isPresented: $showsContact) {
                            Text(contact).font(.dsBody).foregroundStyle(.dsTextPrimary).padding(DS.Space.xl)
                        }
                }
            }
        }
        .font(DS.ComposerSettings.detailFont)
        .lineSpacing(DS.Space.xxs)
        .foregroundStyle(.dsTextSecondary)
        .buttonStyle(SidebarFolderLinkStyle())
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, DS.Sidebar.headerLeading)
        .padding(.trailing, DS.Sidebar.trailing)
        .padding(
            .vertical,
            state.receipt != nil || !state.failures.isEmpty || !state.opening.isEmpty
                || model.folderPolicy.isManaged(.foldersAllowedRoots) ? DS.SidebarFolders.noticeTop : 0
        )
        .padding(.horizontal, DS.Sidebar.inset)
    }

    private var dismiss: some View { Button("Dismiss", action: model.dismissFolderResult) }
}

#if DEBUG
#Preview("Folder result - Added") {
    let app = AppModel.preview()
    app.sidebarFolders.receipt = .init(
        projects: Array(app.projects.all.prefix(1)), previousProject: nil, previousSelection: nil)
    return DSPreviewPair { SidebarFolderResult().frame(width: DS.Size.sidebarWidth) }.sidebarPreviewEnvironment(app)
}
#Preview("Folder result - Expired access") {
    let app = AppModel.preview()
    app.sidebarFolders.failures = [.init(name: "Can’t open atlas", reason: "Folder access expired.")]
    return DSPreviewPair { SidebarFolderResult().frame(width: DS.Size.sidebarWidth) }.sidebarPreviewEnvironment(app)
}
#Preview("Folder result - Opening") {
    let app = AppModel.preview()
    app.sidebarFolders.opening = ["atlas"]
    return DSPreviewPair { SidebarFolderResult().frame(width: DS.Size.sidebarWidth) }.sidebarPreviewEnvironment(app)
}
#Preview("Folder result - Missing, unreadable and rejected") {
    let app = AppModel.preview()
    app.sidebarFolders.failures = [
        .init(name: "atlas", reason: "Can’t find atlas. Locate Folder…", needsLocation: true),
        .init(name: "pier", reason: "Native can’t read pier. Choose Folder…"),
        .init(name: "notes.txt", reason: "Choose a folder to add a project."),
    ]
    return DSPreviewPair { SidebarFolderResult().frame(width: DS.Size.sidebarWidth) }.sidebarPreviewEnvironment(app)
}
#endif
