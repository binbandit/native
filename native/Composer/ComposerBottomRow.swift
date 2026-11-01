import SwiftUI

/// A fixed control layer. Text growth belongs to its parent and never changes this row's height.
struct ComposerBottomRow: View {
    enum Menu: Hashable { case agent, mode, location }

    let state: ComposerRowState
    let actions: ComposerRowActions
    @Binding var openMenu: Menu?

    private var showsContext: Bool {
        state.contextFraction.map { $0.isFinite && $0 > 0.5 } ?? false
    }

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            menuButton(.agent, label: state.agentLabel)
                .layoutPriority(-1)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .popover(isPresented: presented(.agent), arrowEdge: .bottom) {
                    ComposerAgentModelMenu(
                        agents: state.agents, effort: state.effort, notice: state.selectionNotice,
                        chooseModel: { actions.chooseModel($0) }, chooseEffort: actions.chooseEffort,
                        close: { openMenu = nil })
                }
            modeControl
                .fixedSize(horizontal: true, vertical: false)
            locationControl
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: DS.Space.sm)
            IconButton("Attach files (⌘U)", systemImage: "paperclip", size: .large, action: actions.attach)
                .keyboardShortcut("u", modifiers: .command)
                .frame(width: DS.ComposerRow.actionWidth)
            if showsContext {
                contextControl
                    .frame(width: DS.ComposerRow.actionWidth)
            }
            actionControl
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: DS.ComposerRow.height)
        .font(.dsCallout)
    }

    private var modeControl: some View {
        HStack(spacing: 0) {
            menuButton(.mode, label: state.modeLabel)
                .keyboardShortcut("m", modifiers: [.control, .option, .command])
            if !state.isDefaultMode {
                Button {
                    if let id = state.defaultModeID { actions.chooseMode(id) }
                } label: {
                    Image(systemName: "xmark").font(.dsMicro)
                        .frame(width: DS.ComposerRow.actionWidth, height: DS.ComposerRow.controlHeight)
                        .dsHitTarget(DS.ComposerRow.controlHeight)
                }
                .buttonStyle(ComposerRowControlStyle())
                .disabled(state.defaultModeID == nil || !state.canChoose)
                .accessibilityLabel("Remove \(state.modeLabel) mode")
                .help("Restore Full access")
            }
        }
        .background(state.isDefaultMode ? Color.clear : .dsFill, in: .rect(cornerRadius: DS.Radius.row))
        .popover(isPresented: presented(.mode), arrowEdge: .bottom) {
            ComposerModeMenu(choices: state.modes) {
                actions.chooseMode($0)
                openMenu = nil
            }
        }
    }

    @ViewBuilder
    private var locationControl: some View {
        if !state.locations.isEmpty {
            menuButton(.location, label: state.locationLabel)
                .keyboardShortcut("w", modifiers: [.control, .option, .command])
                .popover(isPresented: presented(.location), arrowEdge: .bottom) {
                    ComposerWhereMenu(choices: state.locations) {
                        actions.chooseLocation($0)
                        openMenu = nil
                    }
                }
        }
    }

    private var contextControl: some View {
        Button(action: actions.context) {
            ContextUsageRing(
                fraction: showsContext ? state.contextFraction ?? 0 : 0, size: DS.ComposerRow.contextDiameter
            )
            .frame(width: DS.ComposerRow.actionWidth, height: DS.ComposerRow.controlHeight)
            .dsHitTarget(DS.ComposerRow.controlHeight)
        }
        .buttonStyle(ComposerRowControlStyle())
        .accessibilityLabel("Show context use")
        .opacity(showsContext ? 1 : 0)
        .allowsHitTesting(showsContext)
        .accessibilityHidden(!showsContext)
        .disabled(!showsContext)
    }

    @ViewBuilder
    private var actionControl: some View {
        if state.isWorking {
            HStack(spacing: DS.Space.xs) {
                if state.isStopping {
                    Text("Stopping").foregroundStyle(.dsTextSecondary)
                }
                ComposerStopButton(
                    isStopping: state.isStopping, isEscapeEnabled: false, shortcutHint: "⌘.", action: actions.stop
                )
                .keyboardShortcut(".", modifiers: .command)
            }
        } else {
            ComposerSendButton(disabledReason: state.disabledReason, action: actions.send)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func menuButton(_ menu: Menu, label: String) -> some View {
        Button {
            openMenu = openMenu == menu ? nil : menu
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text(label).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.dsMicro)
            }
            .padding(.horizontal, DS.Space.sm)
            .frame(height: DS.ComposerRow.controlHeight)
            .contentShape(.rect)
            .dsHitTarget(DS.ComposerRow.controlHeight)
        }
        .buttonStyle(ComposerRowControlStyle(selected: openMenu == menu))
        .disabled(!state.canChoose)
        .accessibilityLabel(menu == .agent ? "Agent and model" : menu == .mode ? "Mode" : "Where")
        .accessibilityValue(label)
        .help(label)
    }

    private func presented(_ menu: Menu) -> Binding<Bool> {
        Binding(get: { openMenu == menu }, set: { if !$0 { openMenu = nil } })
    }
}

#if DEBUG
#Preview("Composer row - New task") {
    DSPreviewPair { ComposerRowPreviewFixtures.row() }
}
#endif
