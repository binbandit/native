import SwiftUI

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
