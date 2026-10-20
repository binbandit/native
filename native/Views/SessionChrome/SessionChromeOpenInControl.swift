#if DEBUG && NATIVE_SESSION_CHROME_WIP
import SwiftUI

/// Open In where it's one action among a place's tabs: the default app's icon, which opens the
/// folder there, and its menu of the others on a secondary click.
struct SessionChromeOpenInControl: View {
    let location: OpenInLocation
    var showsName = false

    @State private var isHovered = false

    var body: some View {
        let model = OpenInModel.shared
        let app = model.defaultApp(for: location)
        Button {
            model.openInDefaultApp(location)
        } label: {
            HStack(spacing: DS.Space.xs) {
                if let app {
                    model.icon(for: app)
                        .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                } else {
                    Image(systemName: "doc.on.doc")
                }
                if showsName {
                    Text(app?.name ?? "Copy Path")
                }
            }
            .font(.dsCaption)
            .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, DS.Space.xs)
            .frame(minWidth: DS.Size.controlXS, minHeight: DS.Size.controlXS)
            .background(isHovered ? Color.dsHover : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .trackHover($isHovered)
        .contextMenu { OpenInMenuContent(location: location, model: model) }
        .help(app.map { "Open in \($0.name) (⇧⌘O)" } ?? "Copy Path")
        .accessibilityLabel(app.map { "Open in \($0.name)" } ?? "Copy Path")
    }
}
#endif
