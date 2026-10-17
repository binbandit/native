import SwiftUI

/// A pill that opens a menu: model, mode, autonomy (the reference app's selector chips). Pass a level
/// indicator or status dot as `accessory` to show it after the title.
///
///     PillMenu("Auto Model") { modelButtons } accessory: { EffortBars(level: 2) }
public struct PillMenu<MenuContent: View, Accessory: View>: View {
    let title: String
    let systemImage: String?
    let menu: MenuContent
    let accessory: Accessory

    public init(
        _ title: String,
        systemImage: String? = nil,
        @ViewBuilder menu: () -> MenuContent,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.menu = menu()
        self.accessory = accessory()
    }

    public var body: some View {
        Menu {
            menu
        } label: {
            HStack(spacing: DS.Space.md) {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
                accessory
            }
            .pillChrome()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title)
    }
}

extension PillMenu where Accessory == EmptyView {
    public init(_ title: String, systemImage: String? = nil, @ViewBuilder menu: () -> MenuContent) {
        self.init(title, systemImage: systemImage, menu: menu) { EmptyView() }
    }
}

#Preview("Pill menus") {
    DSPreviewPair {
        HStack(spacing: DS.Composer.controlSpacing) {
            PillMenu("Auto Model") {
                Button("Claude Opus") {}
                Button("GPT-5") {}
            } accessory: {
                EffortBars(level: 2)
            }
            PillMenu("Autonomy") {
                Button("Low") {}
            } accessory: {
                EffortBars(level: 0, isMuted: true)
            }
        }
    }
}
