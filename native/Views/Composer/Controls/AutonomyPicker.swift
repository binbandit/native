import ACP
import NativeCommands
import SwiftUI

/// The autonomy pill's popover: every permission mode the agent offers, least to most autonomous,
/// each with what the agent may do without asking. The current one is checked, the ones the
/// organization forbids are locked, and Plan Mode sits below them, since it suspends whichever is
/// chosen. The footer has the key that steps to the next level.
struct AutonomyPicker: View {
    let setting: SelectSetting
    let levels: [SelectSetting.Choice]
    /// The level in effect, or the one Plan Mode returns to.
    let level: Int
    let agentName: String
    let plan: PlanToggle?
    let onSet: (SelectSetting, String) -> Void
    let onTogglePlan: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What \(agentName) may do without asking")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.xs)
            VStack(spacing: 0) {
                ForEach(levels.indices, id: \.self) { index in
                    levelRow(levels[index], isCurrent: index == level)
                }
            }
            .padding(.horizontal, DS.Space.xs)
            if let plan {
                SeparatorLine()
                    .padding(.vertical, DS.Space.xs)
                planRow(plan)
                    .padding(.horizontal, DS.Space.xs)
            }
            SeparatorLine()
                .padding(.top, DS.Space.xs)
            footer
        }
        .padding(.bottom, DS.Space.xs)
        .frame(width: ComposerMetrics.modelPickerWidth)
    }

    private func levelRow(_ choice: SelectSetting.Choice, isCurrent: Bool) -> some View {
        let isForbidden = PolicyPermissionModes.forbids(setting.option, value: choice.value)
        let isSuspended = plan?.isOn == true && isCurrent
        return AutonomyPickerRow(
            title: choice.name,
            detail: isForbidden ? "Not allowed by your organization" : AutonomySummary.summary(of: choice),
            trailing: isForbidden ? .locked : isCurrent ? .checked(dimmed: isSuspended) : .none,
            isEnabled: !isForbidden
        ) {
            onSet(setting, choice.value)
            dismiss()
        }
        .help(isSuspended ? "Resumes when Plan Mode ends" : choice.description ?? choice.name)
    }

    private func planRow(_ plan: PlanToggle) -> some View {
        AutonomyPickerRow(
            title: "Plan Mode",
            detail: plan.isOn ? "On: the level above resumes when it ends" : AutonomySummary.planMode,
            trailing: plan.isOn ? .checked(dimmed: false) : .none,
            isEnabled: true
        ) {
            onTogglePlan()
            dismiss()
        }
        .help(plan.plan.description ?? AutonomySummary.planMode)
    }

    private var footer: some View {
        HStack {
            Text("Next level")
            Spacer()
            if let shortcut = CommandRegistry.shared.shortcut(for: .sessionNextPermissionMode) {
                Kbd(shortcut.displayString)
            }
        }
        .font(.dsCaption)
        .foregroundStyle(.dsTextTertiary)
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
    }
}

/// One line of the autonomy popover: a name over a plain description, and a check or a lock.
private struct AutonomyPickerRow: View {
    enum Trailing: Equatable {
        case none
        case checked(dimmed: Bool)
        case locked
    }

    let title: String
    let detail: String?
    let trailing: Trailing
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title)
                        .font(.dsCallout)
                        .foregroundStyle(isEnabled ? .dsTextPrimary : .dsTextTertiary)
                    if let detail {
                        Text(detail)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                trailingMark
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(
                isHovered && isEnabled ? Color.dsSelected : .clear,
                in: .rect(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .trackHover($isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(trailing == .checked(dimmed: false) ? .isSelected : [])
    }

    @ViewBuilder
    private var trailingMark: some View {
        switch trailing {
        case .none:
            EmptyView()
        case .checked(let dimmed):
            // The accent can be monochrome, so the current level gets a check, not only a color.
            Image(systemName: "checkmark")
                .font(.dsCaption)
                .foregroundStyle(dimmed ? .dsTextTertiary : .dsAccentText)
                .accessibilityLabel("Current")
        case .locked:
            Image(systemName: "lock.fill")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .accessibilityLabel("Locked")
        }
    }
}
