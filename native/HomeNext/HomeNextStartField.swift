import ACP
import SwiftUI
import UniformTypeIdentifiers

/// Home's start field: the composer at rest, writing Quick Entry's draft to Quick Entry's address.
/// The panel, the Compose page and this field are one draft in three sizes, so ⇧⌘N carries what's
/// typed here onto the page, and every start goes through the same validation and policy.
struct HomeNextStartField: View {
    /// A start that stays on Home, for its receipt.
    let started: (StartingTask) -> Void

    @Environment(AppModel.self) private var model
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool
    @State private var isAddressOpen = false
    @State private var isPickingFiles = false
    @State private var isDoorHovered = false
    @State private var pending: [ComposerPendingAttachment] = []

    var body: some View {
        @Bindable var entry = model.quickEntry
        ComposerSurface(isFloating: true) {
            if !entry.attachments.isEmpty || !pending.isEmpty {
                ComposerAttachmentsSection(
                    attachments: entry.attachments, pending: pending, missing: [], selected: nil,
                    capabilities: model.quickEntryRuntime?.capabilities?.prompt ?? .init(),
                    agentName: agentName ?? "the agent",
                    onRemove: { id in entry.attachments.removeAll { $0.id == id } })
            }
            if let failure = entry.failure {
                Text(failure)
                    .font(.dsCaption).foregroundStyle(.dsAttention)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.ComposerSettings.textInsets.leading)
                    .padding(.vertical, DS.Space.md)
                    .accessibilityIdentifier("home-next-start-failure")
            }
            HStack(alignment: .bottom, spacing: 0) {
                ComposerEditor(
                    text: $entry.draft, selection: $selection, placeholder: placeholder, isFocused: $isFocused,
                    inputLabel: "New task", insets: DS.ComposerSettings.textInsets, onKey: handleKey)
                HStack(spacing: DS.Space.sm) {
                    door
                    attachButton
                    if entry.hasMessage {
                        ComposerSendButton(disabledReason: startBlockedReason) { start(open: false) }
                            .frame(width: DS.Size.composerAction, height: DS.Size.composerAction)
                            .accessibilityLabel("Start task")
                            .help("Start and stay on Home (Return). Start and open with ⌘Return.")
                            .transition(.opacity)
                    }
                }
                .frame(minHeight: DS.ComposerSettings.inputHeight - 2 * DS.ComposerSettings.trailingInset)
                .padding(DS.ComposerSettings.trailingInset)
            }
            .frame(minHeight: DS.ComposerSettings.inputHeight)
        }
        .frame(maxWidth: DS.HomeNext.column)
        .padding(.horizontal, DS.Space.xxl)
        .padding(.bottom, DS.Space.xl)
        .animation(.dsQuick, value: entry.hasMessage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Start a task")
        .onAppear(perform: model.prepareHomeNextStart)
        .onChange(of: model.homeNext.startFieldFocusRequests) { isFocused = true }
        .onChange(of: model.projects.all.map(\.id)) { model.prepareHomeNextStart() }
        .onChange(of: model.quickEntryRuntimes.map(\.agent.id)) { model.reconcileQuickEntryAgent() }
        // Validation names the part of the address to fix; Home opens it where the address lives.
        .onChange(of: entry.picker) { _, picker in
            if picker != nil, ownsAddress { isAddressOpen = true }
        }
        .fileImporter(
            isPresented: Binding(
                get: { entry.isChoosingFolder && ownsAddress }, set: { entry.isChoosingFolder = $0 }),
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result { Task { await model.addQuickEntryProject(url) } }
        }
        .fileImporter(isPresented: $isPickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) {
            if case .success(let urls) = $0 { attach(urls) }
        }
    }

    /// The panel and the page draw their own address while they're open over or instead of Home.
    private var ownsAddress: Bool { !model.quickEntry.isPresented && !model.composeTask.isPresented }

    private var agentName: String? { model.quickEntryRuntime?.agent.displayName }
    private var projectName: String? { model.quickEntry.project.flatMap(model.projects.project)?.name }

    /// "Start a Codex task in native"
    private var placeholder: String {
        switch (agentName, projectName) {
        case (let agent?, let project?): "Start a \(agent) task in \(project)"
        case (nil, let project?): "Start a task in \(project)"
        default: "Start a task"
        }
    }

    private var startBlockedReason: String? {
        pending.isEmpty ? nil : "Wait for the attached files to finish reading"
    }

    private var door: some View {
        Button {
            isAddressOpen.toggle()
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text(model.quickEntryModelName ?? agentName ?? "Choose Agent").lineLimit(1)
                Image(systemName: "chevron.down").font(.dsMicro)
            }
            .font(.dsBody)
            .foregroundStyle(isAddressOpen || isDoorHovered ? .dsTextPrimary : .dsTextTertiary)
            .padding(.horizontal, DS.Space.sm)
            .frame(height: DS.ComposerSettings.controlHeight)
            .background(
                isAddressOpen ? Color.dsSelected : isDoorHovered ? .dsHover : .clear,
                in: .rect(cornerRadius: DS.Radius.control)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isDoorHovered)
        .dsHitTarget(DS.ComposerSettings.controlHeight)
        .accessibilityLabel("Task address")
        .accessibilityValue(
            [agentName, model.quickEntryModelName, model.deviceName(model.quickEntry.device), projectName]
                .compactMap(\.self).joined(separator: ", ")
        )
        .help("Choose the agent, device and project")
        .popover(isPresented: $isAddressOpen, arrowEdge: .top) {
            HomeNextStartAddress(model: model, entry: model.quickEntry).dsPopoverBackground()
        }
        .onChange(of: isAddressOpen) { _, open in
            if !open {
                model.quickEntry.picker = nil
                isFocused = true
            }
        }
    }

    private var attachButton: some View {
        Button {
            isPickingFiles = true
        } label: {
            Image(systemName: "paperclip")
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.ComposerSettings.controlHeight, height: DS.ComposerSettings.controlHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .dsHitTarget(DS.ComposerSettings.controlHeight)
        .accessibilityLabel("Attach Files")
        .help("Attach files…")
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !PlatformTextInput.isComposing else { return .ignored }
        if press.key == .escape {
            isFocused = false
            return .handled
        }
        guard press.key == .return, press.modifiers.isDisjoint(with: [.shift, .option, .control]) else {
            return .ignored
        }
        guard press.phase != .repeat else { return .handled }
        start(open: press.modifiers.contains(.command))
        return .handled
    }

    private func start(open: Bool) {
        guard startBlockedReason == nil, let task = model.startHomeNextTask(open: open) else { return }
        selection = nil
        if !open { started(task) }
    }

    /// Files are read off the main actor; each shows as a chip until it lands.
    private func attach(_ urls: [URL]) {
        let entry = model.quickEntry
        let room = max(PromptAttachment.Limits.count - entry.attachments.count - pending.count, 0)
        let accepted = urls.prefix(room)
        let chips = accepted.map { ComposerPendingAttachment(name: $0.lastPathComponent) }
        pending += chips
        isFocused = true
        Task {
            for (url, chip) in zip(accepted, chips) {
                do {
                    entry.attachments.append(try await Self.read(url))
                } catch {
                    entry.failure = "Couldn't attach \(url.lastPathComponent). \(error.localizedDescription)"
                }
                pending.removeAll { $0.id == chip.id }
            }
            if urls.count > accepted.count {
                entry.failure = "A message holds up to \(PromptAttachment.Limits.count) files."
            }
        }
    }

    private nonisolated static func read(_ url: URL) async throws -> PromptAttachment {
        try PromptAttachment.load(url)
    }
}

#if DEBUG
#Preview("Next start - Rest, typed and failure") {
    HomeNextPreviewFixtures.startField()
}
#endif
