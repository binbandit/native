#if DEBUG
import ACP
import SwiftUI

/// The requested state matrix uses the shipped row, caption, field door and receipt components.
/// This fixture is inert; behavioral checks exercise model actions through an in-memory host.
struct ComposerAgentModelPreview: View {
    let stateID: String
    @State private var isOpen = true

    static var requested: String? {
        UserDefaults.standard.string(forKey: "agentModelFixture")
    }

    private var switched: Bool { stateID == "A4" }
    private var closed: Bool { ["A0", "A4", "A8", "A10"].contains(stateID) }
    private var settings: ComposerSettings {
        switched
            ? ComposerSettingsPreviewFixtures.codex(mode: "read-only")
            : ComposerSettingsPreviewFixtures.claude(mode: "default", models: Self.sourceModels)
    }

    private var entries: [ComposerAgentModel] {
        var models = Self.models(
            settings: ComposerSettingsPreviewFixtures.claude(models: Self.sourceModels),
            agent: "claude-code", name: "Claude Code")
        if stateID != "A5" {
            let foreign = Self.models(settings: ComposerSettingsPreviewFixtures.codex(), agent: "codex", name: "Codex")
            models +=
                stateID == "A7"
                ? Array(foreign.prefix(2)).map {
                    var row = $0; row.isManaged = true; row.unavailable = "Not allowed"; return row
                } : foreign
        }
        if ["A11", "A12"].contains(stateID) {
            models += Self.models(
                settings: ComposerSettingsPreviewFixtures.claude(models: ComposerSettingsPreviewFixtures.gatewayModels),
                agent: "gateway", name: "Gateway")
        }
        return models
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            HStack {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Keep edited messages in place").font(.dsTitle)
                    Text("native · fix/queue-order").font(.dsCaption).foregroundStyle(.dsTextTertiary)
                }
                Spacer()
                Text(switched ? "Codex" : "Claude Code").font(.dsCallout).foregroundStyle(.dsTextSecondary)
            }
            Spacer(minLength: DS.Space.md)
            if !closed {
                HStack {
                    Spacer()
                    popover
                        .background(.dsOverlay, in: .rect(cornerRadius: DS.Radius.card))
                        .overlay {
                            RoundedRectangle(cornerRadius: DS.Radius.card)
                                .strokeBorder(.dsSeparator, lineWidth: DS.AgentChange.dividerHeight)
                        }
                }
            } else {
                Text("The queue now preserves its order. Tests cover editing, moving and sending a queued message.")
                    .font(.dsBody).foregroundStyle(.dsTextPrimary)
                    .frame(maxWidth: DS.Size.contentColumn, alignment: .leading)
                Spacer()
            }
            if stateID == "A4" || stateID == "A10" {
                ChangeAgentDivider(
                    agentName: switched ? "Codex" : "Claude Code",
                    modelName: switched ? "6.1 Sol" : "Haiku 5.5",
                    isReversed: stateID == "A10", onUndo: switched ? {} : nil)
            }
            VStack(spacing: 0) {
                if let receiptText {
                    ComposerAgentReceipt(
                        text: receiptText, isWorking: stateID == "A3",
                        actionTitle: stateID == "A4" ? "Undo" : ["A3", "A8"].contains(stateID) ? "Cancel" : nil,
                        action: {})
                }
                HStack(spacing: DS.Space.lg) {
                    Text(
                        ["A2", "A3", "A4", "A10"].contains(stateID)
                            ? "Also test editing the middle message." : "Message Claude Code"
                    )
                    .font(.dsBody).foregroundStyle(.dsTextSecondary)
                    Spacer()
                    ComposerSettingsDoorLabel(mode: nil, model: switched ? "6.1 Sol" : "Haiku 5.5", isOpen: !closed)
                    Image(systemName: "paperclip").font(.dsBody).foregroundStyle(.dsTextTertiary)
                }
                .padding(DS.ComposerSettings.textInsets)
                .frame(minHeight: DS.ComposerSettings.inputHeight)
            }
            .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
        }
        .padding(DS.Space.xxl)
        .frame(maxWidth: DS.ComposerSettings.width + DS.Space.xxl * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.dsBackground)
        .padding(.leading, DS.Size.sidebarWidth)
    }

    private var receiptText: String? {
        switch stateID {
        case "A3": "Starting Codex…"
        case "A4": "Using Codex · 6.1 Sol"
        case "A8": "Next model: 6.1 Sol · Codex"
        case "A10": "Using Claude Code · Haiku 5.5"
        default: nil
        }
    }

    private var popover: ComposerSettingsPopover {
        let focus = entries.first { $0.agent.rawValue == "codex" }?.id ?? ""
        return ComposerSettingsPopover(
            settings: settings, agentName: "Claude Code", workspace: "fix/queue-order",
            manager: stateID == "A7" ? "Northwind Federal IT" : nil,
            managementExplanation: stateID == "A7" ? "Only approved agents are available." : nil,
            rows: ComposerSettingsPreviewFixtures.rows(), agentModels: entries,
            currentAgentID: .init(rawValue: "claude-code"),
            loadingModelID: stateID == "A3" ? focus : nil,
            onChooseAgentModel: { _ in }, onAgentsSettings: {},
            failure: stateID == "A6"
                ? .init(
                    optionID: "agent-model", message: "Couldn't start Codex. Claude Code is still selected.", retry: {})
                : nil,
            onSet: { _, _ in }, query: stateID == "A11" ? "Sol" : stateID == "A12" ? "nebula" : "",
            hovered: stateID == "A2" ? .model(focus) : nil,
            highlighted: stateID == "A9" || stateID == "A13" ? .model(focus) : nil,
            page: stateID == "A13" ? .model : nil)
    }

    private static let sourceModels = """
        {"value":"haiku","name":"Haiku 5.5","description":"Fastest for quick answers · $1/$5 per Mtok"},
        {"value":"sonnet","name":"Sonnet 5.5"},{"value":"opus","name":"Opus 5.5"}
        """

    private static func models(settings: ComposerSettings, agent: String, name: String) -> [ComposerAgentModel] {
        settings.model?.choices.map {
            .init(agent: .init(rawValue: agent), agentName: name, choice: $0, kind: .model($0.value))
        } ?? []
    }
}

#Preview("Models - A0 rest, A1 open, A2 hover") {
    DSPreviewPair {
        HStack { ForEach(["A0", "A1", "A2"], id: \.self) { ComposerAgentModelPreview(stateID: $0) } }.frame(
            width: 2600, height: 850)
    }
}
#Preview("Models - A3 preparing, A4 applied, A5 no other ready") {
    DSPreviewPair {
        HStack { ForEach(["A3", "A4", "A5"], id: \.self) { ComposerAgentModelPreview(stateID: $0) } }.frame(
            width: 2600, height: 850)
    }
}
#Preview("Models - A6 failure, A7 managed, A8 waiting") {
    DSPreviewPair {
        HStack { ForEach(["A6", "A7", "A8"], id: \.self) { ComposerAgentModelPreview(stateID: $0) } }.frame(
            width: 2600, height: 850)
    }
}
#Preview("Models - A9 keyboard, A10 reversed") {
    DSPreviewPair {
        HStack { ForEach(["A9", "A10"], id: \.self) { ComposerAgentModelPreview(stateID: $0) } }.frame(
            width: 1740, height: 850)
    }
}
#Preview("Models - A11 filtered, A12 no match, A13 touch page") {
    DSPreviewPair {
        HStack { ForEach(["A11", "A12", "A13"], id: \.self) { ComposerAgentModelPreview(stateID: $0) } }.frame(
            width: 2600, height: 850)
    }
}
#endif
