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
    let dismiss: () -> Void

    @Environment(\.hostLookStore) private var injectedLooks
    @State private var highlighted: SessionDevice?
    @FocusState private var isFocused: Bool

    private var looks: HostLookStore {
        injectedLooks ?? .shared
    }

    var body: some View {
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
        .frame(width: HostsMetrics.pickerWidth)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in
            handleKey(press)
        }
        .onAppear {
            highlighted = selection
            isFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run on")
    }

    private func row(_ option: SessionDeviceOption, number: Int) -> some View {
        let isSelected = option.device == selection
        let isHighlighted = option.device == highlighted
        return Button {
            choose(option)
        } label: {
            HostDevicePickerRow(
                option: option, look: look(of: option), projectName: projectName,
                isSelected: isSelected
            )
            .background(
                isHighlighted && option.canStart ? Color.dsSelected : .clear,
                in: .rect(cornerRadius: DS.Radius.control, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!option.canStart)
        .dsHitTarget(DS.Size.controlMD)
        .onHover { isHovering in
            if isHovering, option.canStart { highlighted = option.device }
        }
        .help(number <= 9 ? "\(option.name) (\(number))" : option.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func look(of option: SessionDeviceOption) -> HostLook {
        lookOf?(option) ?? looks.look(for: option.device, named: option.name)
    }

    private func choose(_ option: SessionDeviceOption) {
        guard option.canStart else { return }
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
        let startable = options.filter(\.canStart).map(\.device)
        guard !startable.isEmpty else { return }
        guard let current = highlighted.flatMap(startable.firstIndex(of:)) else {
            highlighted = step > 0 ? startable.first : startable.last
            return
        }
        highlighted = startable[(current + step + startable.count) % startable.count]
    }
}

/// One device in the picker: its glyph and name, its state, and its checkout or what keeps it from
/// taking the session.
struct HostDevicePickerRow: View {
    let option: SessionDeviceOption
    let look: HostLook
    let projectName: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            // A symbol sits on the text's baseline, like a letter.
            HostGlyph(look: look, size: HostsMetrics.calloutGlyph, isDimmed: !option.canStart)
                .frame(width: DS.Size.rowLeading)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.md) {
                    Text(option.name)
                        .font(.dsCallout)
                        .foregroundStyle(option.canStart ? .dsTextPrimary : .dsTextTertiary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.md)
                    // This Mac is always there, so only hosts say whether they're reachable.
                    if showsAvailability {
                        HStack(spacing: DS.Space.xs) {
                            HostAvailabilityMark(availability: option.availability)
                            Text(option.availability.statusTitle)
                        }
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .fixedSize()
                    }
                }
                subtitleText
            }
            // The accent can be monochrome, so the chosen device gets a check too.
            Image(systemName: "checkmark")
                .font(.dsCaption)
                .foregroundStyle(.dsAccentText)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.name)
        .accessibilityValue(
            (showsAvailability ? [option.availability.statusTitle, subtitle] : [subtitle]).joined(separator: ", "))
    }

    private var showsAvailability: Bool {
        option.device != .thisMac
    }

    /// A checkout on one line, cut in the middle of its path (the whole path is in the tooltip); a
    /// reason it can't take the session in full, up to two lines.
    @ViewBuilder private var subtitleText: some View {
        let text = Text(subtitle)
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
        if case .present(let path) = option.checkout, shownPath != nil {
            text
                .lineLimit(1)
                .truncationMode(.middle)
                .help(path)
        } else {
            text
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The checkout's path when the line shows it, with the home folder as ~.
    private var shownPath: String? {
        guard case .present(let path) = option.checkout, !isOffline else { return nil }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private var isOffline: Bool {
        if case .offline = option.availability { true } else { false }
    }

    /// The checkout it would work in, or why it can't take the session.
    private var subtitle: String {
        if case .offline(let reason) = option.availability { return reason }
        return switch option.checkout {
        case .present: "Has \(projectName) · \(shownPath ?? "")"
        case .willClone: "Clones \(projectName) here first"
        case .cannotClone(let reason): reason
        }
    }
}
