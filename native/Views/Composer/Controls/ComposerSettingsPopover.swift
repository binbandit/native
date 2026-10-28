import ACP
import NativePolicy
import SwiftUI

/// The one settings door (`docs/keyboard.md`, "Task settings"): the model and its effort, when the
/// agent asks, then the task's rows, in one column with one text edge, sized to its content so it
/// never scrolls. Values come from the agent's options as they change; the caller applies choices.
struct ComposerSettingsPopover: View {
    /// A choice sent to the agent and not yet confirmed.
    struct Pending: Equatable {
        let optionID: String
        let value: String
    }

    /// A change the agent didn't make, said under its section with the action that retries it.
    struct Failure {
        let optionID: String
        let message: String
        var retry: (() -> Void)?
    }

    enum Page: Equatable {
        /// A menu row's choices, for the keyboard and touch.
        case choices(String)
        /// The model list, on touch, where it would crowd the door.
        case model
    }

    enum Target: Hashable {
        case model(String)
        case agent(AgentDefinition.ID)
        case effort
        case autonomy(String)
        case row(String)
        case fastMode, retry, restart, back, agentsSettings, moreModels
        case command(row: String, index: Int)
    }

    let settings: ComposerSettings
    let agentName: String
    /// Where the agent works freely, named in the captions (the task's branch).
    var workspace: String?
    var manager: String?
    var managementExplanation: String?
    var permissionsManaged = false
    var forbiddenModes: Set<String> = []
    /// Shows "Not allowed" on a forbidden level instead of its consequence (Compose).
    var showsLockedConsequences = true
    /// Compose lists its agents above the settings.
    var leadingContent: AnyView?
    var rows: [ComposerSettingsTaskRow] = []
    var agentModels: [ComposerAgentModel]?
    var currentAgentID: AgentDefinition.ID?
    var modelChange: ComposerAgentChange?
    var loadingModelID: String?
    var onChooseAgentModel: ((ComposerAgentModel) -> Void)?
    var onChooseAgent: ((AgentDefinition.ID) -> Void)?
    var highlightsAgent = false
    var onAgentsSettings: (() -> Void)?
    /// While Plan suspends the permission level, the level it returns to.
    var resumedAutonomy: String?
    var pending: Pending?
    var failure: Failure?
    /// The agent stopped: every value stays readable, none can change, and Restart is offered.
    var isStopped = false
    var onRestart: (() -> Void)?
    /// Opened from the keyboard: the current model starts highlighted.
    var highlightsCurrent = false
    var onClose: () -> Void = {}
    var onUndo: (() -> Void)?
    let onSet: (SelectSetting, String) -> Void

    @State var modelSlots = ModelChoiceList.slots
    @State var query = ""
    @State var hovered: Target?
    @State var highlighted: Target?
    @State var page: Page?
    @State var usesNativeTraversal = false
    @State var typeAhead = ComposerSettingsTypeAhead()
    @FocusState var isFocused: Bool
    @FocusState var isFilterFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch page {
            case .choices(let id):
                if let row = rows.first(where: { $0.id == id }) { choicesPage(row) }
            case .model:
                modelPage
            case nil:
                ComposerSettingsHeightLayout {
                    ViewThatFits(in: .vertical) {
                        mainContent(slots: ModelChoiceList.slots, showsCaptions: true)
                        mainContent(slots: ModelChoiceList.slots - 1, showsCaptions: true)
                        mainContent(slots: ModelChoiceList.slots - 1, showsCaptions: false)
                        // Extra agent settings can exhaust the budget even with captions hidden.
                        // Keep their actions and row heights; the Model page holds the overflow.
                        mainContent(slots: 4, showsCaptions: false)
                        mainContent(slots: 3, showsCaptions: false)
                        mainContent(slots: 2, showsCaptions: false)
                        mainContent(slots: 1, showsCaptions: false)
                    }
                }
            }
        }
        .padding(.vertical, DS.ComposerSettings.popoverInset)
        .frame(width: DS.ComposerSettings.popoverWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            isFocused = true
            if highlightsAgent, let currentAgentID {
                highlighted = .agent(currentAgentID)
            } else if highlightsCurrent, let currentModelID {
                highlighted = .model(currentModelID)
            }
        }
        .onChange(of: currentAgentID) {
            query = ""
            hovered = nil
            highlighted = nil
            page = nil
        }
        .onKeyPress(phases: [.down, .repeat]) { handleKey($0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Task Settings")
    }

    @ViewBuilder private func mainContent(slots: Int, showsCaptions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isStopped {
                stoppedNotice
            }
            if let leadingContent {
                leadingContent
            }
            if agentModels != nil, onChooseAgent != nil {
                agentSection.composerSettingsSection(ruled: isStopped || leadingContent != nil)
            }
            // Stopped values stay dimmed and disabled; overflow navigation stays available.
            Group {
                modelSection(slots: slots, showsCaption: showsCaptions)
                    .composerSettingsSection(
                        ruled: isStopped || leadingContent != nil || (agentModels != nil && onChooseAgent != nil))
                if settings.autonomy != nil {
                    autonomySection(showsCaption: showsCaptions).composerSettingsSection(ruled: true).disabled(
                        isStopped)
                }
                if !rows.isEmpty {
                    taskRows.composerSettingsSection(ruled: true).disabled(isStopped)
                }
            }
            if let manager {
                footer(manager)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { modelSlots = slots }
        .onChange(of: slots) { modelSlots = slots }
    }

    // MARK: - Notice and footer

    private var stoppedNotice: some View {
        HStack(alignment: .center, spacing: DS.Space.md) {
            Text(
                "\(Text("\(agentName) stopped.").font(DS.ComposerSettings.detailMediumFont).foregroundStyle(.dsTextPrimary)) Changes apply once it runs again."
            )
            .font(DS.ComposerSettings.detailFont)
            .foregroundStyle(.dsTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let onRestart {
                Button("Restart", action: onRestart)
                    .buttonStyle(.ds(.secondary, size: .small))
                    .composerSettingsCommandFocus(highlighted == .restart)
            }
        }
        .composerSettingsTextEdge()
        .padding(.top, DS.Space.xxs)
        .padding(.bottom, DS.Space.md)
    }

    private func footer(_ manager: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: "lock")
                .font(DS.ComposerSettings.lockFont)
                .frame(width: DS.ComposerSettings.selectionWidth, height: DS.ComposerSettings.lineHeight)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(
                    "Managed by \(Text(manager).font(DS.ComposerSettings.detailMediumFont).foregroundStyle(.dsTextSecondary)).\(managementExplanation.map { " " + $0 } ?? "")"
                )
                Text(ComposerSettingsPolicyNote.howToChange)
                    .foregroundStyle(.dsTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(DS.ComposerSettings.detailFont)
        .foregroundStyle(.dsTextTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.ComposerSettings.ruleInset)
        .padding(.top, DS.Space.md + DS.Space.xxs)
        .padding(.bottom, DS.Space.xs)
        .overlay(alignment: .top) { ComposerSettingsRule() }
        .accessibilityElement(children: .combine)
    }

    // MARK: - When the agent asks

    /// The level the rows check: the current one, or while Plan suspends it, the one Plan returns to.
    var shownAutonomy: String? {
        settings.isAutonomySuspended ? resumedAutonomy : settings.autonomy?.value
    }

    func isForbidden(_ value: String) -> Bool {
        forbiddenModes.contains(value)
    }

    private func autonomySection(showsCaption: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ComposerSettingsHeader(title: "When \(agentName) asks") {
                if permissionsManaged {
                    Image(systemName: "lock").font(DS.ComposerSettings.lockFont)
                        .accessibilityLabel("Managed by \(manager ?? "your organization")")
                }
            }
            if let autonomy = settings.autonomy {
                ForEach(settings.autonomyLevels) { choice in
                    autonomyRow(choice, setting: autonomy)
                }
                if !isStopped && (showsCaption || failure?.optionID == autonomy.option.id) {
                    autonomyCaption(autonomy)
                }
            }
        }
    }

    private func autonomyRow(_ choice: SelectSetting.Choice, setting: SelectSetting) -> some View {
        let target = Target.autonomy(choice.value)
        let locked = isForbidden(choice.value)
        let mark: ComposerSettingsMark =
            locked ? .lock : mark(for: setting, value: choice.value, isCurrent: choice.value == shownAutonomy)
        return Button {
            choose(target, closing: false)
        } label: {
            ComposerSettingsRow(mark: mark, highlight: highlight(of: target), isDimmed: locked || isStopped) {
                Text(choice.askingTitle)
            } trailing: {
                if locked && !showsLockedConsequences {
                    Text("Not allowed").font(DS.ComposerSettings.detailFont).foregroundStyle(.dsTextTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .composerSettingsHover(target, hovered: $hovered)
        .accessibilityLabel(choice.askingTitle)
        .accessibilityValue(locked ? "Managed by \(manager ?? "your organization")" : "")
        .help(caption(for: choice) ?? choice.askingTitle)
        .accessibilityHint(caption(for: choice) ?? "")
        .accessibilityAddTraits(choice.value == shownAutonomy ? .isSelected : [])
    }

    func caption(for choice: SelectSetting.Choice) -> String? {
        choice.askingCaption(agentName: agentName, workspace: workspace)
    }

    private func autonomyCaption(_ autonomy: SelectSetting) -> some View {
        let levels = settings.autonomyLevels
        let failed = failure.flatMap { $0.optionID == autonomy.option.id ? $0 : nil }
        let previewed: SelectSetting.Choice? =
            switch highlighted ?? hovered {
            case .autonomy(let value): levels.first { $0.value == value }
            default: nil
            }
        let current = levels.first { $0.value == shownAutonomy }
        let isPlanning = settings.plan?.isOn == true
        let text: AttributedString? =
            if let failed {
                AttributedString(failed.message)
            } else if let previewed {
                styled(caption(for: previewed))
            } else if isPlanning {
                planningCaption(then: current)
            } else {
                styled(current.flatMap(caption(for:)))
            }
        let reserving =
            levels.compactMap { styled(caption(for: $0)) } + (isPlanning ? [planningCaption(then: current)] : [])
        return ComposerSettingsCaption(
            text: text, reserving: reserving, isFailure: failed != nil, isKeyboardFocused: highlighted == .retry,
            action: failed?.retry.map { ComposerSettingsTaskRow.Command(title: "Try Again", action: $0) })
    }

    /// While Plan is on: nothing changes until the plan is approved, then the level applies.
    private func planningCaption(then level: SelectSetting.Choice?) -> AttributedString {
        var lead = AttributedString("Planning first.")
        lead.font = DS.ComposerSettings.detailMediumFont
        lead.foregroundColor = .dsTextPrimary
        let then: String =
            switch level?.askingTitle {
            case "Never": " Then it never asks."
            case let title?: " Then it asks \(title.prefix(1).lowercased() + title.dropFirst())."
            case nil: ""
            }
        return lead + AttributedString(" \(agentName) changes nothing until you approve its plan.\(then)")
    }

    /// The caption with the workspace's name set like a branch.
    func styled(_ caption: String?) -> AttributedString? {
        guard let caption else { return nil }
        var text = AttributedString(caption)
        if let workspace, let range = text.range(of: workspace) {
            text[range].font = .dsMonoCaption
            text[range].foregroundColor = .dsTextPrimary
        }
        return text
    }

    // MARK: - Marks and highlight

    /// The gutter of a choice: the loader on the one waiting for the agent (once the wait shows),
    /// else the check on the current one.
    func mark(for setting: SelectSetting, value: String, isCurrent: Bool) -> ComposerSettingsMark {
        if let pending, pending.optionID == setting.option.id {
            return pending.value == value ? .loading : .none
        }
        return isCurrent ? .check : .none
    }

    func highlight(of target: Target) -> ComposerSettingsHighlight {
        if highlighted == target { return .keyboard }
        if hovered == target { return .hover }
        return .none
    }
}

/// How to change something the organization manages, with its own contact when it names one.
enum ComposerSettingsPolicyNote {
    @MainActor static var howToChange: String {
        PolicyCenter.shared.policy.organizationContact.map { "To change it, ask in \($0)." }
            ?? "To change it, ask your organization."
    }
}

extension View {
    /// Tracks the pointer over a row for the popover, which lights it and previews it in its caption.
    func composerSettingsHover(
        _ target: ComposerSettingsPopover.Target, hovered: Binding<ComposerSettingsPopover.Target?>
    ) -> some View {
        onHover { inside in
            withAnimation(inside ? nil : .dsHoverOut) {
                if inside {
                    hovered.wrappedValue = target
                } else if hovered.wrappedValue == target {
                    hovered.wrappedValue = nil
                }
            }
        }
    }
}
