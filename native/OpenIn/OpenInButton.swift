import SwiftUI

/// the reference app's "Open in" control for a task's folder: a split button sized for the window toolbar.
/// The left half opens the folder in the default app and shows that app's real icon; the chevron
/// lists every installed editor, terminal and git client (see `OpenInMenu`).
///
///     ToolbarItem { OpenInButton(folder: session.cwd) }
///         .sharedBackgroundVisibility(.hidden)
///
/// It draws its own outline, so in a toolbar hide the shared glass background as above.
struct OpenInButton: View {
    let folder: URL
    private let model: OpenInModel

    @Environment(\.isEnabled) private var isEnabled
    @State private var isPrimaryHovered = false
    @State private var isChevronHovered = false
    @State private var isMenuOpen = false

    init(folder: URL, model: OpenInModel = .shared) {
        self.folder = folder
        self.model = model
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        HStack(spacing: 0) {
            primary
            Rectangle()
                .fill(.dsBorder)
                .frame(width: 1)
            chevron
        }
        .frame(height: DS.Size.controlXS)
        .background(.dsSurface)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.dsBorder, lineWidth: 1) }
        .fixedSize()
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open In")
    }

    private var primary: some View {
        let app = model.defaultApp
        let title = app.map { "Open in \($0.name)" } ?? "Open"
        return Button {
            model.openInDefaultApp(folder)
        } label: {
            Group {
                if let app {
                    Image(nsImage: model.icon(for: app))
                } else {
                    Image(systemName: "folder")
                        .foregroundStyle(.dsTextSecondary)
                }
            }
            .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
            .padding(.horizontal, DS.Space.sm)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(SegmentButtonStyle(isHovered: isPrimaryHovered && isEnabled))
        .trackHover($isPrimaryHovered)
        .disabled(app == nil)
        .help("\(title) (\(OpenInCommands.shortcut.displayString))")
        .accessibilityLabel(title)
    }

    private var chevron: some View {
        let isHighlighted = isEnabled && (isChevronHovered || isMenuOpen)
        return OpenInMenuTrigger(label: "Open In…", isHovered: $isChevronHovered, isOpen: $isMenuOpen) {
            OpenInMenu.make(folder: folder, model: model)
        }
        .frame(width: DS.Size.rowLeading + 2 * DS.Space.sm)
        .background(isMenuOpen ? .dsPressed : isHighlighted ? .dsHover : .clear)
        .overlay {
            Image(systemName: "chevron.down")
                .font(.dsCaptionMedium)
                .imageScale(.small)
                .foregroundStyle(isHighlighted ? .dsTextPrimary : .dsTextSecondary)
                .allowsHitTesting(false)
        }
        .allowsHitTesting(isEnabled)
    }
}

/// One half of the control: no chrome of its own, a hover wash and a pressed fill.
private struct SegmentButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? .dsPressed : isHovered ? .dsHover : .clear)
    }
}

#Preview("Open In") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            OpenInButton(folder: URL(filePath: NSTemporaryDirectory()))
            OpenInButton(folder: URL(filePath: NSTemporaryDirectory()))
                .disabled(true)
        }
    }
}
