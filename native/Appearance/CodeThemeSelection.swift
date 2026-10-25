import CodeThemes
import Foundation
import NativePolicy

/// Writes the existing preferences together, so a two-mode change is one undoable action.
final class CodeThemeSelection {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func select(_ id: String, for appearance: CodeAppearance?, undoManager: UndoManager?) {
        let light = appearance == .dark ? current(AppearancePreferences.lightCodeThemeKey) : id
        let dark = appearance == .light ? current(AppearancePreferences.darkCodeThemeKey) : id
        apply(light: light, dark: dark, undoManager: undoManager)
    }

    private func current(_ key: String) -> String { defaults.string(forKey: key) ?? CodeTheme.native.id.rawValue }

    private func apply(light: String, dark: String, undoManager: UndoManager?) {
        guard PolicyCenter.shared.policy.appearanceCodeTheme == nil else { return }
        let beforeLight = current(AppearancePreferences.lightCodeThemeKey)
        let beforeDark = current(AppearancePreferences.darkCodeThemeKey)
        guard beforeLight != light || beforeDark != dark else { return }
        defaults.set(light, forKey: AppearancePreferences.lightCodeThemeKey)
        defaults.set(dark, forKey: AppearancePreferences.darkCodeThemeKey)
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.apply(light: beforeLight, dark: beforeDark, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Code Theme")
    }
}
