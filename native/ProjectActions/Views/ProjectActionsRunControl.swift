import SwiftUI
import Terminal

/// The header control's rendering, independent of the runner so every transient state is previewable.
struct ProjectActionsRunControl<MenuContent: View>: View {
    let name: String?
    var state: ProjectActionRunState?
    var runningNames: [String] = []
    var showsFinished = false
    var isFolderRemoved = false
    var projectName = "native"
    var shortcut: String?
    var interaction = ProjectActionsRunInteraction.rest
    let perform: () -> Void
    @ViewBuilder let menuContent: () -> MenuContent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRunHovered = false
    @State private var isChevronHovered = false
    @State private var isMenuOpen = false
    @FocusState private var isPrimaryFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        HStack(spacing: 0) {
            if name != nil {
                primary
                Rectangle().fill(.dsBorder).frame(width: DS.RunControl.borderWidth)
                chevron
            } else {
                emptyMenu
            }
        }
        .frame(height: DS.Size.controlXS)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.dsBorder, lineWidth: DS.RunControl.borderWidth) }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run")
    }

    private var primary: some View {
        Button(action: perform) {
            runLabel
        }
        .buttonStyle(
            ProjectActionsSegmentStyle(
                isHovered: runHovered,
                isHighlighted: state?.isRunning == true || state?.hasFailed == true || showsFinished,
                isPressed: interaction == .pressed, hasSurface: true)
        )
        .trackHover($isRunHovered)
        .disabled(isFolderRemoved)
        .opacity(isFolderRemoved ? 0.5 : 1)
        .help(help)
        .accessibilityLabel(actionLabel)
        .accessibilityValue(accessibilityValue)
        .dsHitTarget(DS.Size.controlXS)
        .dsFocusShape(leadingShape)
        .focused($isPrimaryFocused)
        .task { isPrimaryFocused = interaction == .focus }
    }

    private var runLabel: some View {
        HStack(spacing: DS.Space.sm) {
            glyph
                .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
            HStack(spacing: DS.Space.xxs) {
                Text(name ?? "Run")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: DS.RunControl.labelMaxWidth)
                if runningNames.count > 1 {
                    Text("+\(runningNames.count - 1)")
                        .font(.dsMonoCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
        }
        .font(.dsBody)
        .tracking(DS.Tracking.tight)
        .padding(.leading, DS.Space.sm + DS.RunControl.borderWidth)
        .padding(.trailing, DS.Space.md)
        .frame(maxHeight: .infinity)
        .contentShape(.rect)
    }

    private var chevron: some View {
        let open = isMenuOpen || interaction == .menuOpen
        let hovered = isChevronHovered || interaction == .hoverChevron
        return PlatformProjectActionsMenuTrigger(
            projectName: projectName, isHovered: $isChevronHovered, isOpen: $isMenuOpen, content: menuContent
        )
        .frame(width: DS.Size.rowLeading + 2 * DS.Space.sm + DS.RunControl.borderWidth)
        .background(open ? .dsPressed : hovered ? .dsHover : .clear)
        .overlay {
            Image(systemName: "chevron.down")
                .font(.dsCaption)
                .imageScale(.small)
                .padding(.trailing, DS.RunControl.borderWidth)
                .foregroundStyle(open || hovered ? .dsTextPrimary : .dsTextSecondary)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .trackHover($isChevronHovered)
        .help("Actions for \(projectName)")
        .dsHitTarget(DS.Size.controlXS)
        .dsFocusShape(trailingShape)
    }

    private var emptyMenu: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "play")
                .font(DS.RunControl.playFont)
                .offset(x: DS.RunControl.playOffset)
                .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
            Text("Run").font(.dsBody).tracking(DS.Tracking.tight)
            Image(systemName: "chevron.down").font(.dsCaption).imageScale(.small)
        }
        .padding(.horizontal, DS.Space.sm + DS.RunControl.borderWidth)
        .frame(maxHeight: .infinity)
        .foregroundStyle(isMenuOpen || runHovered ? .dsTextPrimary : .dsTextSecondary)
        .background(isMenuOpen ? .dsPressed : runHovered ? .dsHover : .clear)
        .background(.dsSurface)
        .accessibilityHidden(true)
        .overlay {
            PlatformProjectActionsMenuTrigger(
                projectName: projectName, isSingle: true, isHovered: $isRunHovered, isOpen: $isMenuOpen,
                content: menuContent
            )
            .dsHitTarget(DS.Size.controlXS)
            .dsFocusShape(RoundedRectangle(cornerRadius: DS.Radius.control))
        }
        .trackHover($isRunHovered)
        .help("Actions for \(projectName)")
    }

    @ViewBuilder private var glyph: some View {
        Group {
            if state?.isRunning == true, state?.isStopping != true, !runHovered {
                DotGridLoader(pattern: .waiting).foregroundStyle(.dsTextSecondary)
                    .transition(.opacity)
            } else if state?.hasFailed == true, !runHovered {
                DotGridMark(.failed).foregroundStyle(.dsDanger)
                    .transition(.opacity)
            } else {
                Image(systemName: symbol)
                    .font(symbolFont)
                    .offset(x: symbol == "play" ? DS.RunControl.playOffset : 0)
                    .foregroundStyle(
                        state?.isStopping == true ? AnyShapeStyle(.dsTextTertiary) : AnyShapeStyle(.foreground)
                    )
                    .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                    .transition(.opacity)
            }
        }
        .animation(.dsStandard, value: state)
        .animation(.dsStandard, value: showsFinished)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        if state?.isRunning == true { return "stop.fill" }
        if showsFinished, !runHovered { return "checkmark" }
        return "play"
    }

    private var symbolFont: Font {
        switch symbol {
        case "stop.fill": DS.RunControl.stopFont
        case "checkmark": DS.RunControl.finishedFont
        default: DS.RunControl.playFont
        }
    }

    private var runHovered: Bool {
        !isFolderRemoved && (isRunHovered || interaction == .hoverRun || interaction == .pressed)
    }

    private var actionLabel: String {
        let name = name ?? "Run"
        if state?.isStopping == true { return "End \(name) Now" }
        if state?.isRunning == true { return "Stop \(name)" }
        return "Run \(name)"
    }

    private var help: String {
        if isFolderRemoved { return "This task's folder was removed" }
        let keys = shortcut.map { " (\($0))" } ?? ""
        if case .finished(let outcome) = state, state?.hasFailed == true {
            return "\(outcome.summary(of: name ?? "Action")). Run it again\(keys)"
        }
        if case .couldNotStart(let reason) = state {
            return "\(name ?? "Action") couldn't start: \(reason) Run it again\(keys)"
        }
        return actionLabel + (state?.isRunning == true ? "" : keys)
    }

    private var accessibilityValue: String {
        if runningNames.count > 1 { return "\(runningNames.formatted()) running" }
        if state?.isStopping == true { return "Stopping" }
        if state?.isRunning == true { return "Running" }
        if case .finished(.exited(let status?, _)) = state, status != 0 { return "Failed, exit code \(status)" }
        if case .couldNotStart(let reason) = state { return "Couldn't start: \(reason)" }
        return showsFinished ? "Finished" : ""
    }

    private var leadingShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: DS.Radius.control, bottomLeadingRadius: DS.Radius.control)
    }

    private var trailingShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomTrailingRadius: DS.Radius.control, topTrailingRadius: DS.Radius.control)
    }
}

private struct ProjectActionsSegmentStyle: ButtonStyle {
    var isHovered = false
    var isHighlighted = false
    var isPressed = false
    var hasSurface = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed || isPressed
        configuration.label
            .foregroundStyle(pressed || isHovered || isHighlighted ? .dsTextPrimary : .dsTextSecondary)
            .background(pressed ? .dsPressed : isHovered ? .dsHover : .clear)
            .background(hasSurface ? .dsSurface : .clear)
    }
}

/// Explicit interaction states let the canvas show the same fills used by live pointer and keyboard input.
enum ProjectActionsRunInteraction {
    case rest, hoverRun, pressed, hoverChevron, menuOpen, focus
}

#if DEBUG
#Preview("Run - Control") { ProjectActionsRunPreview() }
#endif
