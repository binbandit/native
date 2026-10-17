import SwiftUI

/// A sidebar navigation row: icon, label, an optional shortcut hint that appears on hover and an
/// optional trailing accessory such as a menu (Factory `NavigationButton`: 6pt padding, 10pt gap,
/// 12pt icons, secondary text that turns primary on hover).
public struct SidebarNavItem<Accessory: View>: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let shortcut: String?
    let action: () -> Void
    let accessory: Accessory

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    /// - Parameter shortcut: A hint such as "⌘N", shown at the trailing edge while hovered.
    public init(
        _ title: String,
        systemImage: String,
        isSelected: Bool = false,
        shortcut: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.shortcut = shortcut
        self.action = action
        self.accessory = accessory()
    }

    public var body: some View {
        let isHighlighted = (isHovered && isEnabled) || isSelected
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .regular))
                        .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                    Text(title)
                        .font(.dsCallout)
                        .tracking(DS.Tracking.snug)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let shortcut {
                        Text(shortcut)
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                            .opacity(isHovered ? 1 : 0)
                            .animation(.easeOut(duration: 0.12), value: isHovered)
                    }
                }
                .padding(DS.Space.sm)
                .frame(minHeight: DS.Size.minimumHitTarget)
                .contentShape(.rect)
            }
            .buttonStyle(SidebarRowButtonStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .help(shortcut.map { "\(title) (\($0))" } ?? title)

            accessory
        }
        // Accessories fill the row's height without stretching it.
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(isHighlighted ? .dsTextPrimary : .dsTextSecondary)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isSelected ? .dsSelected : isHovered && isEnabled ? .dsHover : .clear)
        }
        .opacity(isEnabled ? 1 : 0.5)
        .trackHover($isHovered)
    }
}

extension SidebarNavItem where Accessory == EmptyView {
    public init(
        _ title: String,
        systemImage: String,
        isSelected: Bool = false,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) {
        self.init(title, systemImage: systemImage, isSelected: isSelected, shortcut: shortcut, action: action) {
            EmptyView()
        }
    }
}

/// Darkens a sidebar row while pressed (Conductor's `active:inset-shadow` 10% wash). Hover and
/// selection fills belong to the row so they also cover trailing accessories.
public struct SidebarRowButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .fill(configuration.isPressed ? .dsPressed : .clear)
            }
    }
}

/// A small trailing menu for a sidebar row, e.g. choosing which agent "New Session" starts.
public struct SidebarRowMenu<Content: View>: View {
    let label: String
    let systemImage: String
    let content: Content

    public init(label: String, systemImage: String = "chevron.down", @ViewBuilder content: () -> Content) {
        self.label = label
        self.systemImage = systemImage
        self.content = content()
    }

    public var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .semibold))
                .frame(width: 20)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .dsHitTarget(20)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, DS.Space.xxs)
        .help(label)
        .accessibilityLabel(label)
    }
}

#Preview("Sidebar navigation") {
    DSPreviewPair {
        VStack(spacing: 0) {
            SidebarNavItem("New Session", systemImage: "plus", shortcut: "⌘N") {
            } accessory: {
                SidebarRowMenu(label: "Choose an Agent") {
                    Button("Claude Code") {}
                    Button("Codex") {}
                }
            }
            SidebarNavItem("Mission Control", systemImage: "flag", isSelected: true) {}
            SidebarNavItem("Search", systemImage: "magnifyingglass", shortcut: "⌘K") {}
        }
        .frame(width: 232)
    }
}
