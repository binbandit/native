import SwiftUI

/// Address pickers share the settings menu's leading selection column and type scale.
struct HostDeviceAddressRow: View {
    let option: SessionDeviceOption
    let look: HostLook
    let projectName: String
    let isSelected: Bool
    let offlineSince: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            Image(systemName: "checkmark").font(DS.ComposerSettings.rowFont)
                .opacity(isSelected ? 1 : 0)
                .frame(width: DS.ComposerSettings.selectionWidth)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: look.symbol.systemImage)
                        .foregroundStyle(option.canStart ? .dsTextSecondary : .dsTextTertiary)
                        .frame(width: DS.ComposerSettings.selectionWidth)
                    Text(option.name).font(DS.ComposerSettings.rowFont).lineLimit(1)
                    Spacer(minLength: DS.Space.sm)
                    HStack(spacing: DS.Space.xs) {
                        if case .offline = option.availability {
                            StatusDot(color: .dsTextTertiary)
                        } else {
                            HostAvailabilityMark(availability: option.availability)
                        }
                        Text(option.availability.statusTitle)
                    }
                    .font(.dsCaption).foregroundStyle(.dsTextTertiary).fixedSize()
                }
                .frame(height: DS.ComposerSettings.rowHeight)
                detail.font(.dsCaption).foregroundStyle(.dsTextTertiary)
                    .padding(.leading, DS.ComposerSettings.selectionWidth + DS.Space.sm)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, DS.Space.xs)
        }
        .font(DS.ComposerSettings.rowFont)
        .padding(.horizontal, DS.Space.xs)
        .foregroundStyle(option.canStart ? .dsTextPrimary : .dsTextTertiary)
        .accessibilityElement(children: .combine)
    }

    private var detail: Text {
        if case .offline = option.availability {
            return Text(offlineSince.map { "Not reachable since \($0)" } ?? "Not reachable")
        }
        switch option.checkout {
        case .present(let path):
            let abbreviated = (path as NSString).abbreviatingWithTildeInPath
            return Text("Has \(projectName) at \(Text(abbreviated).font(DS.ComposerReference.pathFont))")
        case .willClone: return Text("Clones \(projectName) here first")
        case .cannotClone(let reason): return Text(reason)
        }
    }
}

#if DEBUG
#Preview("Device address rows - Online and offline") {
    DSPreviewPair {
        VStack {
            ForEach(HostDeviceFixtures.options) { option in
                HostDeviceAddressRow(
                    option: option, look: .fallback(for: option.device, named: option.name),
                    projectName: "native", isSelected: option.device == .thisMac, offlineSince: "2:14 PM")
            }
        }.padding(DS.ComposerSettings.sectionInset).frame(width: DS.ComposeTask.popoverWidth)
    }
}
#endif
