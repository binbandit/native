import AppKit
import SwiftUI

/// The chevron's menu: every installed app with its own icon, grouped into editors, terminals, git
/// clients and Finder, with the default checked and showing its shortcut, then Copy Path.
///
/// Choosing an app opens the folder there and makes it the default, as in the reference app, so setting the
/// default and using it are one step and the button always shows where you went last.
enum OpenInMenu {
    static func make(for location: OpenInLocation, model: OpenInModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let defaultID = model.defaultApp?.id
        for (index, group) in model.appGroups.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            for app in group {
                menu.addItem(item(for: app, isDefault: app.id == defaultID, location: location, model: model))
            }
        }
        menu.addItem(.separator())
        let copyIcon = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        let copyPath = NSMenuItem("Copy Path", image: copyIcon) { model.copyPath(of: location) }
        // Shown so its title lines up with the apps' (a hidden image leaves no gap).
        copyPath.preferredImageVisibility = .visible
        menu.addItem(copyPath)
        return menu
    }

    private static func item(
        for app: OpenInApp,
        isDefault: Bool,
        location: OpenInLocation,
        model: OpenInModel
    ) -> NSMenuItem {
        let item = NSMenuItem(app.name, image: model.icon(for: app)) { model.open(location, in: app) }
        // macOS 27 hides menu images by default; an app's icon is how you spot it, as in Open With.
        item.preferredImageVisibility = .visible
        if isDefault {
            item.state = .on
            item.setKeyEquivalent(OpenInCommands.shortcut)
        }
        return item
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
