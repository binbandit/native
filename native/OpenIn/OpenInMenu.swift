import AppKit
import SwiftUI

/// The chevron's menu: every installed app with its own icon, grouped into editors, terminals, git
/// clients and Finder, with the default checked and showing its shortcut, then Copy Path.
///
/// Choosing an app opens the folder there and makes it the default (Conductor's behavior). Holding
/// Option turns every other app into "Set <app> as Default", which changes the default without
/// opening anything.
enum OpenInMenu {
    static func make(folder: URL, model: OpenInModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let defaultID = model.defaultApp?.id
        for (index, group) in model.appGroups.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            for app in group {
                addItems(for: app, isDefault: app.id == defaultID, folder: folder, model: model, to: menu)
            }
        }
        menu.addItem(.separator())
        let copyIcon = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(NSMenuItem("Copy Path", image: copyIcon) { model.copyPath(of: folder) })
        return menu
    }

    /// The app's row; every app but the default gets an Option alternate that only sets the default.
    private static func addItems(for app: OpenInApp, isDefault: Bool, folder: URL, model: OpenInModel, to menu: NSMenu) {
        let icon = model.icon(for: app)
        let item = NSMenuItem(app.name, image: icon) { model.open(folder, in: app) }
        menu.addItem(item)
        if isDefault {
            item.state = .on
            item.setKeyEquivalent(OpenInCommands.shortcut)
        } else {
            let alternate = NSMenuItem("Set \(app.name) as Default", image: icon) { model.setDefault(app) }
            alternate.keyEquivalentModifierMask = .option
            alternate.isAlternate = true
            menu.addItem(alternate)
        }
    }
}

/// A menu item that runs a closure. NSMenuItem holds its target weakly, so the item also keeps
/// the closure alive as its represented object.
private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}

extension NSMenuItem {
    fileprivate convenience init(_ title: String, image: NSImage?, action handler: @escaping () -> Void) {
        let action = MenuAction(handler)
        self.init(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        target = action
        representedObject = action
        self.image = image
    }

    /// Shows a shortcut the menu bar owns. The menu is only up while it's tracking, so it never
    /// competes with the menu bar for the keys.
    fileprivate func setKeyEquivalent(_ shortcut: KeyboardShortcut) {
        keyEquivalent = String(shortcut.key.character)
        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) { mask.insert(.command) }
        if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
        if shortcut.modifiers.contains(.option) { mask.insert(.option) }
        if shortcut.modifiers.contains(.control) { mask.insert(.control) }
        keyEquivalentModifierMask = mask
    }
}
