import SwiftUI

/// The app icon chooser for a settings row: the settings select (an outlined 32pt trigger with an
/// up-down chevron) showing the current icon's thumbnail and name. It opens a popover listing every
/// option with its thumbnail, its source and limits, and a checkmark on the current one.
///
/// A popover rather than a menu: menus draw images at 16pt and template-tint some, too small to
/// tell icon themes apart, and have no room for a plugin's name or a "Mac only" note. The list
/// still behaves like a menu: arrow keys move, Return chooses, Escape closes, and choosing closes.
///
///     IconThemePicker("App icon", selection: $choice, options: options)
public struct IconThemePicker<ID: Hashable>: View {
    let title: String
    @Binding var selection: ID
    let options: [IconThemeOption<ID>]
    let previewScheme: ColorScheme?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresented = false
    @State private var isHovered = false

    /// - Parameters:
    ///   - title: What VoiceOver calls the control, and the popover's name.
    ///   - previewScheme: Which of each option's images to show; nil follows the window's appearance.
    ///     Pass the user's icon appearance when it can differ from the window's.
    public init(
        _ title: String,
        selection: Binding<ID>,
        options: [IconThemeOption<ID>],
        previewScheme: ColorScheme? = nil
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.previewScheme = previewScheme
    }

    private var isDark: Bool {
        (previewScheme ?? colorScheme) == .dark
    }

    private var current: IconThemeOption<ID>? {
        options.first { $0.id == selection }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: DS.Space.sm) {
                if let current {
                    IconThemeThumbnail(image: current.image(isDark: isDark), size: DS.IconPicker.triggerThumbnail)
                }
                Text(current?.title ?? "Choose…")
                    .font(.ds(14))
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.dsTextSecondary)
            }
            .padding(.leading, DS.Space.sm)
            .padding(.trailing, DS.Space.md)
            .frame(minWidth: DS.IconPicker.triggerMinWidth, maxWidth: DS.IconPicker.triggerMaxWidth)
            .frame(height: DS.Size.controlMD)
            .background(isHovered || isPresented ? Color.dsHover : Color.dsBackground, in: shape)
            .overlay { shape.strokeBorder(.dsBorder, lineWidth: 1) }
            .contentShape(shape)
            .dsHitTarget(DS.Size.controlMD)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .dsFocusShape(shape)
        .trackHover($isHovered)
        .accessibilityLabel(title)
        .accessibilityValue(current?.title ?? "None")
        .accessibilityHint("Shows the icons to choose from")
        .dsPopover(isPresented: $isPresented, arrowEdge: .bottom) {
            IconThemeList(title: title, selection: $selection, options: options, isDark: isDark) {
                isPresented = false
            }
        }
    }
}

extension DS {
    /// The icon picker's sizes. Its rows and trigger follow the settings rows' 32pt controls.
    public enum IconPicker {
        /// The current icon beside its name in the trigger.
        public static let triggerThumbnail: CGFloat = 20
        public static let triggerMinWidth: CGFloat = 140
        public static let triggerMaxWidth: CGFloat = 240
        /// Each option's icon in the list: big enough to tell themes apart at a glance.
        public static let rowThumbnail: CGFloat = 32
        #if os(iOS)
        public static let rowHeight: CGFloat = 52
        #else
        public static let rowHeight: CGFloat = 44
        #endif
        public static let listWidth: CGFloat = 288
        /// The list scrolls past this many rows' worth.
        public static let listMaxHeight: CGFloat = 400
    }
}

/// An icon image at a thumbnail size, smoothly scaled.
struct IconThemeThumbnail: View {
    let image: Image
    let size: CGFloat

    var body: some View {
        image
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Icon theme picker") {
    DSPreviewPair {
        GalleryIconThemePicker()
    }
}
#endif
