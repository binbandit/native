import SwiftUI

/// Where a new session runs: This Mac and each paired host, each saying whether it's online,
/// connecting or offline (and why), and whether it has the project. Devices that can't take the
/// session now stay listed, dimmed, with the reason, so nothing just goes missing.
///
/// The list takes the keyboard when it opens: ↑ and ↓ move between the devices that can take the
/// session, Return picks, 1 to 9 pick a device by its place, Escape closes (`docs/keyboard.md`,
/// "Choosing a device"). Every row is also a button, for the pointer and touch.
struct HostDevicePicker: View {
    let options: [SessionDeviceOption]
    let projectName: String
    @Binding var selection: SessionDevice
    /// Opens Add Host; the footer offers it when set.
    var onAddHost: (() -> Void)?
    /// Each device's look, when the caller knows more than its name (its machine name, for the
    /// symbol it has until the user picks one).
    var lookOf: ((SessionDeviceOption) -> HostLook)?
    /// Nil when embedded across a containing panel, as in Quick Entry.
    var width: CGFloat? = HostsMetrics.pickerWidth
    var allowsOfflineHold = false
    var offlineSince: ((SessionDevice) -> String?)?
    let dismiss: () -> Void

    @Environment(\.hostLookStore) private var injectedLooks
    @State private var highlighted: SessionDevice?
    @FocusState private var isFocused: Bool

    private var looks: HostLookStore {
        injectedLooks ?? .shared
    }

    var body: some View {
        Group {
            if allowsOfflineHold {
                addressRows
            } else {
                standardRows
            }
        }
        .frame(width: width)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in handleKey(press) }
        .onAppear {
            highlighted = selection
            isFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run on")
    }

    private var standardRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Run on")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.xs)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    row(option, number: index + 1)
                }
            }
            .padding(DS.Space.xs)
            if let onAddHost {
                SeparatorLine()
                Button {
                    dismiss()
                    onAddHost()
                } label: {
                    Label("Add Host…", systemImage: "plus")
                        .font(.dsCallout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.ds(.ghost, size: .medium))
                .padding(DS.Space.xs)
            }
        }
    }

    private var addressRows: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Run on").font(.dsCaption).foregroundStyle(.dsTextTertiary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    row(option, number: index + 1)
                }
                if let onAddHost {
                    SeparatorLine().padding(.vertical, DS.Space.xs)
                    Button {
                        dismiss()
                        onAddHost()
                    } label: {
                        HStack(spacing: DS.Space.sm) {
                            Image(systemName: "plus").font(DS.ComposerSettings.rowFont).foregroundStyle(
                                .dsTextSecondary
                            )
                            .frame(width: DS.ComposerSettings.selectionWidth)
                            Text("Add Host…").font(DS.ComposerSettings.rowFont)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, DS.Space.xs)
                        .frame(height: DS.ComposerSettings.rowHeight)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.dsTextPrimary)
                }
            }
        }
        .padding(DS.ComposerSettings.sectionInset)
        .padding(DS.ComposerSettings.popoverInset)
    }

    private func row(_ option: SessionDeviceOption, number: Int) -> some View {
        let isSelected = option.device == selection
        let isHighlighted = option.device == highlighted
        return Button {
            choose(option)
        } label: {
            Group {
                if allowsOfflineHold {
                    HostDeviceAddressRow(
                        option: option, look: look(of: option), projectName: projectName,
                        isSelected: isSelected, offlineSince: offlineSince?(option.device))
                } else {
                    HostDevicePickerRow(
                        option: option, look: look(of: option), projectName: projectName, isSelected: isSelected)
                }
            }
            .background(
                isHighlighted && canChoose(option) ? Color.dsSelected : .clear,
                in: .rect(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canChoose(option))
        .dsHitTarget(DS.Size.controlMD)
        .onHover { isHovering in
            if isHovering, canChoose(option) { highlighted = option.device }
        }
        .help(number <= 9 ? "\(option.name) (\(number))" : option.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func look(of option: SessionDeviceOption) -> HostLook {
        lookOf?(option) ?? looks.look(for: option.device, named: option.name)
    }

    private func choose(_ option: SessionDeviceOption) {
        guard canChoose(option) else { return }
        selection = option.device
        dismiss()
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Shortcuts with ⌘, ⌥ or ⌃ belong to the app.
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
        switch press.key {
        case .downArrow:
            move(by: 1)
            return .handled
        case .upArrow:
            move(by: -1)
            return .handled
        case .return, .space:
            if let option = options.first(where: { $0.device == highlighted }) { choose(option) }
            return .handled
        case .escape:
            dismiss()
            return .handled
        default:
            guard let number = Int(press.characters), (1...9).contains(number), number <= options.count else {
                return .ignored
            }
            choose(options[number - 1])
            return .handled
        }
    }

    /// The next device in `step`'s direction that can take the session, wrapping around.
    private func move(by step: Int) {
        let startable = options.filter(canChoose).map(\.device)
        guard !startable.isEmpty else { return }
        guard let current = highlighted.flatMap(startable.firstIndex(of:)) else {
            highlighted = step > 0 ? startable.first : startable.last
            return
        }
        highlighted = startable[(current + step + startable.count) % startable.count]
    }
    private func canChoose(_ option: SessionDeviceOption) -> Bool {
        if option.canStart { return true }
        guard allowsOfflineHold, option.device.isRemote else { return false }
        if case .cannotClone = option.checkout { return false }
        return true
    }

}
