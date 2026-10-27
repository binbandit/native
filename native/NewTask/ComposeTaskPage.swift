import Git
import SwiftUI
import UniformTypeIdentifiers

struct ComposeTaskPage: View {
    let model: AppModel
    @Bindable var compose: ComposeTaskModel
    @Bindable var entry: QuickEntryModel
    @Environment(GitStore.self) private var git: GitStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drops = ComposerDropInbox()
    @State private var viewportHeight = CGFloat.infinity

    var body: some View {
        Group {
            if compose.stage == .message || compose.stage == .settled {
                ComposeTaskStartingPage(model: model, compose: compose)
            } else {
                letter
            }
        }
        .background(.dsBackground)
        .focusedSceneValue(\.composeDraft, compose.commandDraft)
        .navigationTitle("New Task")
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("New Task").font(.dsCalloutSemibold)
                    if compose.stage != .writing {
                        Text(subtitle).font(.dsCaption).foregroundStyle(.dsTextTertiary)
                    }
                }
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .principal) { ComposeTaskWell(model: model, compose: compose, entry: entry) }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                if compose.stage == .writing, !entry.device.isRemote || model.composeDeviceOption?.canStart == true {
                    Button {
                        model.startComposeTask()
                    } label: {
                        ComposeKeyLabel(title: compose.second == nil ? "Start" : "Start 2 Tasks")
                    }
                    .buttonStyle(.ds(.primary, size: .medium))
                    .disabled(
                        !compose.hasContent || compose.pendingAttachments || compose.isReadingWorkspaces
                            || compose.stage != .writing || compose.isHeld
                    )
                    .accessibilityLabel(compose.second == nil ? "Start task" : "Start 2 tasks")
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .fileImporter(isPresented: $entry.isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { Task { await model.addQuickEntryProject(url) } }
        }
        .sheet(isPresented: $compose.showsWorkspaces, onDismiss: compose.cancelWorkspaceSelection) {
            TaskWorkspacePickerContent(
                options: compose.workspaces, selection: $compose.workspaceSelection,
                isLoading: compose.isReadingWorkspaces, isChanging: false, error: compose.workspaceFailure,
                cancel: compose.cancelWorkspaceSelection,
                retry: { Task { await model.readComposeWorkspaces() } },
                apply: compose.applyWorkspaceSelection)
        }
        .task(id: "\(String(describing: entry.project))/\(entry.device)") { await loadWorkspace() }
        .task(id: compose.starting?.id) {
            guard compose.starting != nil else { return }
            #if DEBUG
            guard compose.previewState == nil else { return }
            #endif
            if !reduceMotion { try? await Task.sleep(for: DS.ComposeTask.foldDuration) }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : DS.ComposeTask.settle) { compose.stage = .message }
            if !reduceMotion { try? await Task.sleep(for: DS.ComposeTask.settleDuration) }
            guard !Task.isCancelled else { return }
            compose.stage = .settled
            model.finishComposeTransition()
        }
        .onChange(of: model.composeCanRevealTask) { model.finishComposeTransition() }
        .onKeyPress(.escape) {
            if model.composeCanCancelStart {
                model.cancelComposeStart()
                return .handled
            }
            guard entry.picker != nil else { return .ignored }
            entry.picker = nil
            return .handled
        }
        .animation(reduceMotion ? nil : DS.ComposeTask.fold, value: compose.stage)
    }

    private var letter: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: DS.ComposeTask.titleGap) {
                    letterhead.zIndex(entry.picker == .project ? 1 : 0)
                    ComposeTaskAddress(model: model, branch: branch, compose: compose, entry: entry)
                        .disabled(compose.stage != .writing)
                }
                .opacity(compose.stage == .folding ? DS.ComposeTask.foldOpacity : 1)
                .offset(y: compose.stage == .folding && !reduceMotion ? DS.ComposeTask.foldOffset : 0)
                // An open address popover draws over the draft below.
                .zIndex(entry.picker == nil ? 0 : 1)
                draft
            }
            .frame(maxWidth: DS.ComposeTask.width, alignment: .leading)
            .padding(.horizontal, DS.ComposeTask.labelWidth + DS.ComposeTask.labelGap + DS.Space.md)
            .padding(.top, DS.ComposeTask.topInset)
            .padding(.bottom, DS.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .top)
            .background { closesPicker }
        }
        .coordinateSpace(.composeViewport)
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { viewportHeight = $0 }
        .environment(\.composeViewportHeight, viewportHeight)
        .composerDropTarget(drops, isEnabled: !compose.isHeld && compose.stage == .writing)
        .dsToolbarBand()
    }

    private var draft: some View {
        VStack(alignment: .leading, spacing: 0) {
            SeparatorLine().padding(.top, DS.ComposeTask.ruleGap).padding(.bottom, DS.ComposeTask.editorGap)
            if let editor = compose.editor {
                ComposerView(
                    session: editor,
                    page: .init(
                        allowsFileMentions: entry.project != nil && entry.device == .thisMac,
                        needsFolder: entry.project == nil,
                        isSealed: compose.isHeld,
                        openSettings: { entry.toggle(.agent) },
                        start: submitOrClosePicker,
                        attachmentsPending: { compose.pendingAttachments = $0 })
                )
                .id(editor.id)
                .environment(drops)
                // The draft keeps focus under an open address popover, so its keys go to the popover
                // first: Escape closes it, as Return does below, never starting the task behind it.
                .environment(
                    \.composerOverlayDismissal,
                    entry.picker == nil ? nil : ComposerOverlayDismissal { entry.picker = nil }
                )
                .disabled(compose.isHeld || compose.stage != .writing)
            }
            if let failure = entry.failure {
                Text(failure).font(.dsBody).foregroundStyle(.dsAttention)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, DS.Space.xl)
                    .accessibilityIdentifier("compose-failure")
            }
        }
        .overlay { closesPicker }
    }

    private func submitOrClosePicker() {
        if entry.picker != nil {
            entry.picker = nil
        } else {
            model.submitComposeTask()
        }
    }

    /// A click anywhere else on the page closes an open address popover, as outside a system one.
    @ViewBuilder private var closesPicker: some View {
        if entry.picker != nil {
            Color.clear.contentShape(.rect).onTapGesture { entry.picker = nil }.accessibilityHidden(true)
        }
    }

    private var letterhead: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Button {
                entry.toggle(.project)
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Text(projectName).font(.dsDisplay).tracking(DS.Tracking.display)
                        .foregroundStyle(entry.project == nil ? .dsTextTertiary : .dsTextPrimary)
                        .padding(.leading, -DSTypography.displayIndent(of: projectName))
                    if !compose.isHeld {
                        Image(systemName: "chevron.up.chevron.down").font(.dsCallout).foregroundStyle(.dsTextTertiary)
                    }
                }
                .frame(height: DS.ComposeTask.titleHeight)
                .composeFocus(entry.picker == .project, height: DS.ComposeTask.titleHeight)
            }
            .buttonStyle(ComposeAddressButtonStyle()).disabled(compose.isHeld || compose.stage != .writing)
            .accessibilityLabel("Choose task project")
            .composeAddressPopover(isPresented: entry.picker == .project, dismiss: { entry.picker = nil }) {
                QuickEntryPicker(model: model, entry: entry)
                    .frame(width: DS.ComposeTask.popoverWidth).frame(maxHeight: $0)
            }
            .zIndex(entry.picker == .project ? 1 : 0)
            if entry.project == nil {
                Button {
                    entry.isChoosingFolder = true
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        Text("Open Folder…").foregroundStyle(.dsTextSecondary)
                        Kbd("⌘O")
                    }
                    .font(.dsBody)
                    .frame(height: DS.ComposeTask.rowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var projectName: String { entry.project.flatMap(model.projects.project)?.name ?? "Choose a folder" }
    private var branch: String? {
        #if DEBUG
        if let branch = compose.previewBranch { return branch }
        #endif
        guard entry.device == .thisMac, let project = entry.project.flatMap(model.projects.project) else { return nil }
        return git?.model(for: project.url).branch?.name
    }
    private var subtitle: String {
        [projectName, branch, entry.device.isRemote ? model.composeDeviceOption?.name : nil].compactMap { $0 }.joined(
            separator: " · ")
    }
    private func loadWorkspace() async {
        #if DEBUG
        guard compose.previewState == nil else { return }
        #endif
        guard !compose.isHeld else { return }
        await model.readComposeWorkspaces()
        if let project = entry.project.flatMap(model.projects.project), entry.device == .thisMac {
            git?.model(for: project.url).refresh()
        }
    }
}

#if DEBUG
#Preview("Compose - Letter") { ComposeTaskPreviewFixture(state: "ready") }
#Preview("Compose - Empty") { ComposeTaskPreviewFixture(state: "empty") }
#Preview("Compose - First launch") { ComposeTaskPreviewFixture(state: "firstLaunch") }
#Preview("Compose - Offline") { ComposeTaskPreviewFixture(state: "offline") }
#Preview("Compose - Held") { ComposeTaskPreviewFixture(state: "held") }
#Preview("Compose - Devices") { ComposeTaskPreviewFixture(state: "devices") }
#Preview("Compose - Attachments") { ComposeTaskPreviewFixture(state: "attachments") }
#Preview("Compose - Changed defaults") { ComposeTaskPreviewFixture(state: "consequences") }
#Preview("Compose - Two agents") { ComposeTaskPreviewFixture(state: "twoAgents") }
#Preview("Compose - Failure") { ComposeTaskPreviewFixture(state: "failure") }
#Preview("Compose - Narrow") { ComposeTaskPreviewFixture(state: "narrow") }
#endif
