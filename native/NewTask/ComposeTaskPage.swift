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

    var body: some View {
        Group {
            if compose.stage == .message || compose.stage == .settled {
                ComposeTaskStartingPage(model: model, compose: compose)
            } else {
                letter
            }
        }
        .background(.dsBackground)
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
            ToolbarItem(placement: .principal) { TaskWellLabel(content: readiness) }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem {
                if compose.stage == .writing, !entry.device.isRemote || model.composeDeviceOption?.canStart == true {
                    Button {
                        model.startComposeTask()
                    } label: {
                        HStack(spacing: DS.Space.sm) {
                            Text("Start"); Image(systemName: "return")
                        }
                    }
                    .buttonStyle(.ds(.primary, size: .medium))
                    .disabled(
                        !compose.hasContent || compose.pendingAttachments || compose.isReadingWorkspaces
                            || compose.stage != .writing || compose.isHeld
                    )
                    .accessibilityLabel("Start task")
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .fileImporter(isPresented: $entry.isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { Task { await model.addQuickEntryProject(url) } }
        }
        .sheet(isPresented: $compose.showsWorkspaces) {
            TaskWorkspacePickerContent(
                options: compose.workspaces, selection: $compose.workspace,
                isLoading: compose.isReadingWorkspaces, isChanging: false, error: compose.workspaceFailure,
                cancel: { compose.showsWorkspaces = false },
                retry: { Task { await model.readComposeWorkspaces() } },
                apply: { compose.showsWorkspaces = false })
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
        .onChange(of: compose.starting?.openedSession) { model.finishComposeTransition() }
        .onChange(of: compose.starting?.failure) { model.finishComposeTransition() }
        .onKeyPress(.escape) {
            if compose.starting != nil, compose.starting?.openedSession == nil {
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
                    letterhead
                    ComposeTaskAddress(model: model, branch: branch, compose: compose, entry: entry)
                        .disabled(compose.stage != .writing)
                }
                .opacity(compose.stage == .folding ? DS.ComposeTask.foldOpacity : 1)
                .offset(y: compose.stage == .folding && !reduceMotion ? DS.ComposeTask.foldOffset : 0)
                SeparatorLine().padding(.top, DS.ComposeTask.ruleGap).padding(.bottom, DS.ComposeTask.editorGap)
                if let editor = compose.editor {
                    ComposerView(
                        session: editor,
                        page: .init(
                            allowsFileMentions: entry.project != nil && entry.device == .thisMac,
                            needsFolder: entry.project == nil,
                            openSettings: { entry.toggle(.agent) },
                            start: { model.submitComposeTask() },
                            attachmentsPending: { compose.pendingAttachments = $0 })
                    )
                    .id(editor.id)
                    .environment(drops)
                    .focusedSceneValue(\.composeDraft, editor)
                    .disabled(compose.isHeld || compose.stage != .writing)
                }
                if let failure = entry.failure {
                    Text(failure).font(.dsBody).foregroundStyle(.dsAttention)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, DS.Space.xl)
                        .accessibilityIdentifier("compose-failure")
                }
            }
            .frame(maxWidth: DS.ComposeTask.width, alignment: .leading)
            .padding(.horizontal, DS.ComposeTask.labelWidth + DS.ComposeTask.labelGap + DS.Space.md)
            .padding(.top, DS.ComposeTask.topInset)
            .padding(.bottom, DS.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .composerDropTarget(drops, isEnabled: !compose.isHeld && compose.stage == .writing)
        .dsToolbarBand()
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
                    Image(systemName: "chevron.up.chevron.down").font(.dsCallout).foregroundStyle(.dsTextTertiary)
                }
                .frame(height: DS.ComposeTask.titleHeight)
            }
            .buttonStyle(.plain).disabled(compose.isHeld || compose.stage != .writing)
            .accessibilityLabel("Choose task project")
            .dsPopover(
                isPresented: Binding(get: { entry.picker == .project }, set: { if !$0 { entry.picker = nil } }),
                attachmentAnchor: .point(.bottomLeading), arrowEdge: .top
            ) {
                QuickEntryPicker(model: model, entry: entry).frame(width: DS.ComposeTask.popoverWidth)
            }
            if entry.project == nil {
                Button("Open Folder…") { entry.isChoosingFolder = true }.buttonStyle(.ds(.ghost))
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
    private var readiness: TaskWellContent {
        let agent = model.quickEntryRuntime?.agent.displayName ?? compose.editor?.agentName ?? "Choose agent"
        if compose.stage != .writing { return .init(status: .starting, agent: agent, verb: "Starting") }
        if entry.project == nil { return .init(status: .idle, agent: agent, verb: "· Needs a folder") }
        if model.composeDeviceOption?.canStart == false {
            if model.composeDeviceOption?.availability == .connecting {
                return .init(status: .starting, agent: "", verb: "Connecting to \(model.deviceName(entry.device))")
            }
            if model.composeDeviceOption?.availability == .online {
                return .init(status: .needsInput, agent: "", verb: "Needs a checkout")
            }
            return .init(
                status: .needsInput, agent: "",
                verb: "Waiting for \(model.composeDeviceOption?.name ?? model.deviceName(entry.device))")
        }
        if let runtime = model.quickEntryRuntime, runtime.needsSignIn {
            return .init(status: .needsInput, agent: agent, verb: "Sign in to \(agent)")
        }
        if model.quickEntryRuntime?.status == .starting {
            return .init(status: .starting, agent: agent, verb: "Starting")
        }
        if model.quickEntryRuntime == nil {
            return .init(status: .needsInput, agent: "", verb: "Choose an available agent")
        }
        if model.quickEntryRuntime?.isAvailable == false {
            return .init(status: .needsInput, agent: agent, verb: "Needs attention")
        }
        return .init(status: .idle, agent: agent, verb: "· Ready")
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
#Preview("Compose - Failure") { ComposeTaskPreviewFixture(state: "failure") }
#Preview("Compose - Narrow") { ComposeTaskPreviewFixture(state: "narrow") }
#endif
