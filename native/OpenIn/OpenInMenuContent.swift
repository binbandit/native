import SwiftUI

/// The Open In menu as SwiftUI items, for the menu bar's Open In submenu (and the control's menu
/// where AppKit isn't available): the apps that can open the location, the default checked, then
/// Copy Path. Choosing an app opens the folder there and makes it the default.
struct OpenInMenuContent: View {
    let location: OpenInLocation
    let model: OpenInModel

    var body: some View {
        let defaultID = model.defaultApp(for: location)?.id
        Group {
            ForEach(model.appGroups(for: location), id: \.first?.target.kind) { group in
                ForEach(group) { app in
                    Toggle(
                        isOn: Binding {
                            app.id == defaultID
                        } set: { _ in
                            model.open(location, in: app)
                        }
                    ) {
                        Label {
                            Text(app.name)
                        } icon: {
                            model.icon(for: app)
                        }
                    }
                }
                Divider()
            }
            Button("Copy Path", systemImage: "doc.on.doc") {
                model.copyPath(of: location)
            }
        }
        // Menus only show item icons when the content asks for them.
        .labelStyle(.titleAndIcon)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Open In menu") {
    let model = OpenInModel(defaults: PreviewUserDefaults())
    DSPreviewPair {
        // The apps on this Mac that can open a folder, with Copy Path; the default is checked.
        Menu("Open In") {
            OpenInMenuContent(location: .local(URL(filePath: NSTemporaryDirectory())), model: model)
        }
        .fixedSize()
    }
}
#endif
