/// Code themes tried on before one is chosen. Try On previews each theme on a real task until the
/// user keeps one or cancels; this holds what each mode shows meanwhile, which mode's list is up, and
/// what Keep writes. Nothing is written before Keep, so Cancel only has to stop showing `tried`.
///
/// `Backgrounds` is the app's light and dark backgrounds, which this package doesn't know.
public struct ThemeTrial<Backgrounds: Equatable & Sendable>: Equatable, Sendable {
    /// A theme for each mode, and the backgrounds they draw on.
    public struct Choice: Equatable, Sendable {
        public var light: CodeTheme.ID
        public var dark: CodeTheme.ID
        public var backgrounds: Backgrounds

        public init(light: CodeTheme.ID, dark: CodeTheme.ID, backgrounds: Backgrounds) {
            self.light = light
            self.dark = dark
            self.backgrounds = backgrounds
        }

        public subscript(_ appearance: CodeAppearance) -> CodeTheme.ID {
            get { appearance == .dark ? dark : light }
            set {
                switch appearance {
                case .light: light = newValue
                case .dark: dark = newValue
                }
            }
        }
    }

    public enum Ending: Sendable {
        case keep, cancel
    }

    /// What the user had when the trial started.
    public let kept: Choice
    /// What the window shows now.
    public private(set) var tried: Choice
    /// The mode whose themes are listed and previewed.
    public var mode: CodeAppearance
    private var light: [CodeTheme]
    private var dark: [CodeTheme]

    /// - Parameters:
    ///   - light: The themes on offer for light mode, in list order; `dark` likewise.
    public init(kept: Choice, mode: CodeAppearance, light: [CodeTheme], dark: [CodeTheme]) {
        self.kept = kept
        tried = kept
        self.mode = mode
        self.light = light
        self.dark = dark
    }

    public func themes(for appearance: CodeAppearance) -> [CodeTheme] {
        appearance == .dark ? dark : light
    }

    /// The listed mode's themes.
    public var themes: [CodeTheme] { themes(for: mode) }

    /// What `appearance` shows now. A stored theme that isn't on offer (its plugin is off) shows
    /// Native, as it does outside Try On.
    public func shown(_ appearance: CodeAppearance) -> CodeTheme {
        offered(tried[appearance], for: appearance) ?? offered(CodeTheme.native.id, for: appearance)
            ?? themes(for: appearance).first ?? .native
    }

    /// The highlighted row: what the listed mode shows.
    public var highlighted: CodeTheme { shown(mode) }

    /// The theme `appearance` uses outside the trial, marked "In use".
    public func inUse(_ appearance: CodeAppearance) -> CodeTheme {
        offered(kept[appearance], for: appearance) ?? offered(CodeTheme.native.id, for: appearance)
            ?? themes(for: appearance).first ?? .native
    }

    public var hasChanges: Bool { tried != kept }

    public mutating func highlight(_ id: CodeTheme.ID) {
        guard offered(id, for: mode) != nil else { return }
        tried[mode] = id
    }

    /// Moves the highlight `offset` rows, stopping at either end.
    public mutating func move(_ offset: Int) {
        let list = themes
        guard let index = list.firstIndex(of: highlighted) else { return }
        highlight(list[min(max(index + offset, 0), list.count - 1)].id)
    }

    /// Type-select: highlights the first theme whose name starts with `prefix`, ignoring case.
    /// Returns whether one did.
    @discardableResult
    public mutating func highlight(matching prefix: String) -> Bool {
        guard !prefix.isEmpty,
            let match = themes.first(where: { $0.name.lowercased().hasPrefix(prefix.lowercased()) })
        else { return false }
        highlight(match.id)
        return true
    }

    public mutating func setBackgrounds(_ backgrounds: Backgrounds) {
        tried.backgrounds = backgrounds
    }

    /// The themes on offer changed (a plugin was turned off or on). A tried theme that went away
    /// falls back to the kept one; the kept one stays even while it's away, so Keep doesn't lose it.
    public mutating func update(light: [CodeTheme], dark: [CodeTheme]) {
        self.light = light
        self.dark = dark
        for appearance in CodeAppearance.allCases
        where tried[appearance] != kept[appearance] && offered(tried[appearance], for: appearance) == nil {
            tried[appearance] = kept[appearance]
        }
    }

    /// What ending the trial writes: both modes and the backgrounds on Keep, nothing on Cancel.
    public func writes(_ ending: Ending) -> Choice? {
        switch ending {
        case .keep: tried
        case .cancel: nil
        }
    }

    private func offered(_ id: CodeTheme.ID, for appearance: CodeAppearance) -> CodeTheme? {
        themes(for: appearance).first { $0.id == id }
    }
}
