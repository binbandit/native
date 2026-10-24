import ACP
import NativePolicy
import SwiftUI
import UniformTypeIdentifiers

/// One trailing control, including More's agent settings. MCP's existing panel stays in this popover.
struct ComposerSettingsControl: View {
    let session: SessionModel
    let settings: ComposerSettings
    let mode: TaskModeControl
    @Binding var isPresented: Bool
    @Binding var isPickingFiles: Bool
    let onAttach: (IncomingAttachments) -> Void

    @Environment(AppModel.self) private var app
    @Environment(SettingsPresentation.self) private var presentation: SettingsPresentation?
    @Environment(\.mcpServersPopover) private var mcpPresentation
    @State private var showsMCP = false
    @State private var isHovered = false
    @State private var isApplying = false
    @State private var failure: String?

    private var library: MCPLibrary? { MCPServersPlugin.library(in: app.plugins) }
    private var policy: NativePolicy { PolicyCenter.shared.policy }
    private var permissionsManaged: Bool { policy.isManaged(.forbiddenPermissionModes) }

    private var manager: String? {
        let keys: Set<PolicyKey> = [.forbiddenPermissionModes, .mcpAllowed, .mcpBlocked, .mcpRequired]
        return policy.managedKeys.isDisjoint(with: keys) ? nil : policy.organizationName ?? "your organization"
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text(settings.model?.shortModelName ?? "Task Settings")
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.dsMicro)
            }
            .font(.dsBody)
            .foregroundStyle(isPresented || isHovered ? .dsTextPrimary : .dsTextTertiary)
            .padding(.horizontal, DS.Space.sm)
            .frame(height: DS.ComposerSettings.controlHeight)
            .background(
                isPresented ? Color.dsSelected : isHovered ? .dsHover : .clear,
                in: .rect(cornerRadius: DS.Radius.control)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .dsHitTarget()
        .accessibilityLabel("Task Settings")
        .accessibilityValue(settings.model?.shortModelName ?? "Agent defaults")
        .accessibilityIdentifier("composer-settings")
        .help(CommandRegistry.shared.help("Task Settings", for: .sessionChooseModel))
        .focusedSceneValue(\.mcpServersPopover, mcpPresentation)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            content.dsPopoverBackground()
        }
        .fileImporter(isPresented: $isPickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) {
            if case .success(let urls) = $0, !urls.isEmpty { onAttach(.files(urls)) }
        }
        .fileDialogDefaultDirectory(session.cwd)
        .task(id: session.clientID) { await library?.track(session.context) }
        .onChange(of: mcpPresentation?.wrappedValue) { _, show in
            if show == true {
                showsMCP = true
                isPresented = true
            }
        }
        .onChange(of: isPresented) { _, open in
            if !open {
                showsMCP = false
                mcpPresentation?.wrappedValue = false
            }
        }
    }

    @ViewBuilder private var content: some View {
        if showsMCP, let library {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    showsMCP = false
                    mcpPresentation?.wrappedValue = false
                } label: {
                    Label("Task Settings", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .font(.dsBody)
                .padding(DS.Space.lg)
                .dsHitTarget()
                MCPSessionPanel(
                    library: library, session: session, entries: library.entries(forSession: session.clientID),
                    onManage: {
                        isPresented = false
                        presentation?.open(.mcpServers)
                    })
            }
        } else {
            ComposerSettingsPopover(
                settings: settings, agentName: session.agentName, manager: manager,
                permissionsManaged: permissionsManaged, forbiddenModes: policy.forbiddenPermissionModes,
                isApplying: isApplying || session.phase == .disconnected,
                failure: failure
                    ?? (session.phase == .disconnected
                        ? "Settings can change when \(session.agentName) is running again." : nil),
                source: { session.hasChosenConfig($0) ? .user : .agent(session.agentName) }, onSet: set
            ) {
                connections
            } actions: {
                actions
                    .disabled(session.phase == .disconnected)
            }
        }
    }

    private var connections: some View {
        VStack(spacing: DS.Space.xs) {
            Button {
                showsMCP = true
                mcpPresentation?.wrappedValue = true
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "powerplug").foregroundStyle(.dsTextTertiary)
                    Text("MCP servers")
                    Spacer(minLength: DS.Space.sm)
                    if let library {
                        let entries = library.entries(forSession: session.clientID)
                        Text("\(MCPSessionSummary(library: library, entries: entries).active)")
                        Image(systemName: "chevron.right").font(.dsMicro)
                    } else {
                        Text("Extension is off").foregroundStyle(.dsTextTertiary)
                    }
                }
                .font(DS.ComposerSettings.rowFont)
                .frame(minHeight: DS.ComposerSettings.rowHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(library == nil)
            .dsHitTarget()
            .accessibilityLabel("MCP servers")

            // ACP has no universal web-search switch. Only an offered setting may change it.
            if !(settings.modelSwitches + settings.others).contains(where: {
                $0.option.name.localizedCaseInsensitiveCompare("Web search") == .orderedSame
                    || $0.option.category == "web_search"
            }) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "globe")
                    Text("Web search")
                    Spacer(minLength: DS.Space.sm)
                    Text("Not offered by \(session.agentName)")
                        .font(DS.ComposerSettings.detailFont)
                }
                .font(DS.ComposerSettings.rowFont)
                .foregroundStyle(.dsTextTertiary)
                .frame(minHeight: DS.ComposerSettings.rowHeight)
                .help("\(session.agentName) does not expose a web search setting for this task.")
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ModeMenu(control: mode)
                .font(DS.ComposerSettings.rowFont)
            HStack(spacing: DS.Space.sm) {
                AttachButton(isPickingFiles: $isPickingFiles, onPick: onAttach, presentsFilePicker: false)
                Text("Attach files").font(DS.ComposerSettings.rowFont)
                Spacer(minLength: DS.Space.sm)
                SessionGoalControl(session: session, showsIcon: false)
                ContextIndicator(session: session, style: .labeled)
            }
        }
    }

    private func set(_ setting: SelectSetting, _ value: String) {
        guard !isApplying else { return }
        isApplying = true
        failure = nil
        Task {
            await session.pick(setting.option, value: value)
            isApplying = false
            if let updated = session.configOptions.first(where: { $0.id == setting.option.id }),
                let actual = SelectSetting(updated), actual.value != value
            {
                failure = "Couldn't change \(setting.option.name). \(actual.currentName) is still selected. Try again."
            }
        }
    }
}

#if DEBUG
#Preview("Task settings control - Rest and narrow") {
    let app = AppModel.preview()
    if let session = SessionModel.preview(in: app, configOptions: ComposerPreviewFixtures.configOptions) {
        DSPreviewPair {
            ComposerSettingsControl(
                session: session, settings: ComposerSettings(session.configOptions),
                mode: TaskModeControl(
                    session: session,
                    modes: TaskModes(
                        library: ModeLibrary(defaults: PreviewUserDefaults()), defaults: PreviewUserDefaults())),
                isPresented: .constant(false), isPickingFiles: .constant(false), onAttach: { _ in }
            )
            .padding(DS.Space.lg)
        }
        .environment(app)
    }
}
#endif
