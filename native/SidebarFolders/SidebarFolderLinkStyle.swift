import SwiftUI

/// Quiet inline recovery actions have independent touch targets and system focus rings.
struct SidebarFolderLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.ComposerSettings.detailFont)
            .foregroundStyle(configuration.isPressed ? .dsTextSecondary : .dsTextPrimary)
            .frame(minHeight: DS.isTouchPlatform ? DS.Size.minimumHitTarget : DS.SidebarFolders.noticeLineHeight)
            .contentShape(.rect)
            .dsFocusShape(.rect(cornerRadius: DS.Radius.control))
    }
}
