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
        var previousKind: OpenInTarget.Kind?
        for app in model.apps {
            if let previousKind, previousKind != app.target.kind {
                menu.addItem(.separator())
            }
            previousKind = app.target.kind

            let icon = model.icon(for: app)
            let item = ActionMenuItem(app.name, image: icon) { model.open(folder, in: app) }
            if app.id == defaultID {
                item.state = .on
                item.setKeyEquivalent(OpenInCommands.shortcut)
                menu.addItem(item)
            } else {
                menu.addItem(item)
                let alternate = ActionMenuItem("Set \(app.name) as Default", image: icon) { model.setDefault(app) }
                alternate.keyEquivalentModifierMask = .option
                alternate.isAlternate = true
                menu.addItem(alternate)
            }
        }
        menu.addItem(.separator())
        let copyIcon = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        menu.addItem(ActionMenuItem("Copy Path", image: copyIcon) { model.copyPath(of: folder) })
        return menu
    }
}

/// A menu item that runs a closure.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, image: NSImage?, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(perform), keyEquivalent: "")
        target = self
        self.image = image
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("ActionMenuItem is never decoded")
    }

    @objc private func perform() {
        handler()
    }

    /// Shows a shortcut the menu bar owns. The menu is only up while it's tracking, so it never
    /// competes with the menu bar for the keys.
    func setKeyEquivalent(_ shortcut: KeyboardShortcut) {
        keyEquivalent = String(shortcut.key.character)
        var mask: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) { mask.insert(.command) }
        if shortcut.modifiers.contains(.shift) { mask.insert(.shift) }
        if shortcut.modifiers.contains(.option) { mask.insert(.option) }
        if shortcut.modifiers.contains(.control) { mask.insert(.control) }
        keyEquivalentModifierMask = mask
    }
}
